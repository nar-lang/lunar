#!/usr/bin/env lua
---Lunar CLI.
---
---Usage: `lunar [--debug] [--out FILE] [--run MOD.DEF] <file-or-glob>... [-- <script-args>...]`
---
---By default compiles every `.nar` source into a single bytecode file at
---`--out FILE` (default `program.binar`).
---
---With `--run MOD.DEF`, also evaluates that entry in an in-process runtime
---(after loading package natives) and exits with the returned `Int`.
---Anything after a literal `--` is passed to the program as a
---`List String` argument.
---
---If both `--run` and `--out` are given, the file is written *and* the
---program is executed. If only `--run` is given, no file is written
---(bytecode lives in memory for the duration of the process).
---
---Positional arguments accept:
---  * an exact `.nar` file path;
---  * `<dir>/*`     — every `.nar` file directly under `<dir>`;
---  * `<dir>/**/*`  — every `.nar` file recursively under `<dir>`.
---
---Package natives: for each source file, the nearest ancestor directory
---containing `nar.json` is treated as a package root. If that directory
---has an `init.lua` it is `loadfile`d and called as `function(rt)` so it
---can register its native implementations.

-- True only when this file is the program's entry point (not `require`d).
-- For the main script Lua sets `source == "@" .. arg[0]`; for a `require`d
-- chunk the source is the path the loader found, which differs from arg[0].
local _IS_MAIN = arg ~= nil
    and arg[0] ~= nil
    and debug.getinfo(1, "S").source == "@" .. arg[0]

-- When run as a script, prepend the parent of this `lunar/` repo to
-- `package.path` so that `require("lunar.compiler")` etc. resolve
-- without needing an external wrapper / LUA_PATH.
if _IS_MAIN then
    local src = debug.getinfo(1, "S").source
    if src:sub(1, 1) == "@" then
        local path = src:sub(2)
        local function quote(s) return (s:gsub('"', '\\"')) end
        local function dirname(p) return p:match("(.*/)") or "./" end
        local function readlink(p)
            local f = io.popen('readlink -- "' .. quote(p) .. '" 2>/dev/null')
            local r = f and f:read("*l") or nil
            if f then f:close() end
            return (r ~= nil and r ~= "") and r or nil
        end
        -- Canonicalise a path's containing dir the POSIX-portable way.
        local function realdirOf(p)
            local f = io.popen('cd "$(dirname -- "' .. quote(p) .. '")" 2>/dev/null && pwd -P')
            local r = f and f:read("*l") or nil
            if f then f:close() end
            return r or "."
        end
        for _ = 1, 32 do
            local target = readlink(path)
            if target == nil then break end
            if target:sub(1, 1) ~= "/" then
                target = dirname(path) .. target
            end
            path = target
        end
        -- path == .../lunar/cli/init.lua  →  rootDir == .../
        local cliDir   = realdirOf(path)            -- .../lunar/cli
        local lunarDir = realdirOf(cliDir)          -- .../lunar
        local rootDir  = realdirOf(lunarDir) .. "/" -- .../
        package.path   = rootDir .. "?.lua;" .. rootDir .. "?/init.lua;" .. package.path
    end
end

local Compiler = require("lunar.compiler")
local Runtime  = require("lunar.runtime")
local Object   = Runtime.Object

-- ----------------------------------------------------------------------------
-- Tiny IO / FS helpers
-- ----------------------------------------------------------------------------

local function eprintln(s)
    io.stderr:write(s .. "\n")
end

---@param path string
---@return string|nil data, string|nil err
local function readAll(path)
    local f, err = io.open(path, "rb")
    if f == nil then
        return nil, err
    end
    local data = f:read("*a")
    f:close()
    return data
end

---@param path string
---@param data string
---@return boolean ok, string|nil err
local function writeAll(path, data)
    local f, err = io.open(path, "wb")
    if f == nil then
        return false, err
    end
    f:write(data)
    f:close()
    return true
end

---Return the directory part of a path (no trailing slash). Empty string
---means the current directory.
---@param path string
---@return string
local function dirname(path)
    local d = path:match("^(.*)/[^/]+$")
    return d or ""
end

---Walk up from `startDir` until a directory containing `marker` is found.
---Returns the package directory or `nil` if none found.
---@param startDir string
---@param marker string e.g. "nar.json"
---@return string|nil
local function findPackageRoot(startDir, marker)
    local dir = startDir
    if dir == "" then dir = "." end
    while true do
        local probe = dir .. "/" .. marker
        local f = io.open(probe, "rb")
        if f ~= nil then
            f:close()
            return dir
        end
        local parent = dir:match("^(.*)/[^/]+$")
        if parent == nil or parent == dir then
            return nil
        end
        if parent == "" then parent = "/" end
        dir = parent
    end
end

-- ----------------------------------------------------------------------------
-- Argument expansion (globs)
-- ----------------------------------------------------------------------------

---Run a shell command and collect its output lines (sorted).
---@param cmd string
---@return string[]
local function findLines(cmd)
    local p = io.popen(cmd)
    if p == nil then
        return {}
    end
    local out = {}
    for line in p:lines() do
        out[#out + 1] = line
    end
    p:close()
    table.sort(out)
    return out
end

---Expand a single positional argument into a list of `.nar` file paths.
---Accepts:
---  * a literal path (no glob meta);
---  * `<dir>/*` or `<dir>/*.nar` — every `.nar` file directly under `<dir>`;
---  * `<dir>/**/*` or `<dir>/**/*.nar` — every `.nar` file recursively.
---@param pat string
---@return string[]|nil files, string|nil err
local function expandArg(pat)
    if not pat:find("[*?]") then
        return { pat }
    end

    local dir = pat:match("^(.+)/%*%*/%*%.nar$") or pat:match("^(.+)/%*%*/%*$")
    if dir ~= nil then
        return findLines('find "' .. dir .. '" -type f -name "*.nar" 2>/dev/null')
    end

    dir = pat:match("^(.+)/%*%.nar$") or pat:match("^(.+)/%*$")
    if dir ~= nil then
        return findLines('find "' .. dir .. '" -maxdepth 1 -type f -name "*.nar" 2>/dev/null')
    end

    return nil, "unsupported glob pattern `" .. pat .. "` (use `dir/*` or `dir/**/*`)"
end

---Expand a list of positional patterns into a deduplicated, ordered list of
---existing `.nar` file paths. Returns `nil, err` on the first failure.
---@param positional string[]
---@return string[]|nil files, string|nil err
local function collectSources(positional)
    local seen = {}
    local files = {}
    for _, a in ipairs(positional) do
        local matched, gerr = expandArg(a)
        if matched == nil then
            return nil, "lunar: " .. gerr
        end
        if #matched == 0 then
            return nil, "lunar: no .nar files matched `" .. a .. "`"
        end
        for _, f in ipairs(matched) do
            if not seen[f] then
                seen[f] = true
                files[#files + 1] = f
            end
        end
    end
    return files
end

---Read all source files into a `path -> content` table.
---@param files string[]
---@return table<string, string>|nil sources, string|nil err
local function readSources(files)
    local sources = {}
    for _, path in ipairs(files) do
        local content, rerr = readAll(path)
        if content == nil then
            return nil, "lunar: read " .. path .. ": " .. tostring(rerr)
        end
        sources[path] = content
    end
    return sources
end

-- ----------------------------------------------------------------------------
-- Help text
-- ----------------------------------------------------------------------------

local function usage()
    io.stderr:write([[
usage: lunar [--debug] [--out FILE] [--run MOD.DEF] <file-or-glob>... [-- <script-args>...]

Compile Nar sources, and optionally run an entry definition.

Positional arguments (before `--`):
  <file.nar>      a single source file
  <dir>/*         every .nar file directly under <dir>
  <dir>/**/*      every .nar file recursively under <dir>

Flags:
  --debug         emit debug info into the bytecode
  --out FILE      bytecode output path (default: program.binar when --run
                  is not given; otherwise no file is written)
  --run MOD.DEF   after compiling, execute the given entry in an
                  in-process runtime. The entry must have type
                  `(args: List String) -> Int`. Arguments after `--`
                  become the List String; the returned Int is the
                  process exit code.
  -h, --help      show this help

Examples:
  # Compile to program.binar
  lunar Nar.Base/**/*

  # Compile and immediately run an entry def, passing CLI args through
  lunar --run Hello.main Hello.nar Nar.Base/**/* -- one two three

  # Compile to a custom path AND run it
  lunar --out hello.binar --run Hello.main Hello.nar Nar.Base/**/*
]])
end

-- ----------------------------------------------------------------------------
-- Run helpers
-- ----------------------------------------------------------------------------

---Split argv on the first literal `--`. Returns (preArgs, postArgs).
---@param args string[]
local function splitOnDoubleDash(args)
    local pre, post = {}, {}
    local seen = false
    for _, a in ipairs(args) do
        if not seen and a == "--" then
            seen = true
        elseif seen then
            post[#post + 1] = a
        else
            pre[#pre + 1] = a
        end
    end
    return pre, post
end

---Discover all unique package roots (dirs containing `nar.json`) that
---host any of the given source files. Returns dir paths in stable order.
---@param files string[]
---@return string[]
local function discoverPackageRoots(files)
    local seen = {}
    local roots = {}
    for _, path in ipairs(files) do
        local d = dirname(path)
        if d == "" then d = "." end
        local root = findPackageRoot(d, "nar.json")
        if root ~= nil and not seen[root] then
            seen[root] = true
            roots[#roots + 1] = root
        end
    end
    return roots
end

---Load and apply every package's `init.lua` (if any) to the runtime.
---
---We use `loadfile` rather than `require` because Lua's require translates
---dots in the module name into path separators (so `require("Nar.Base")`
---looks for `Nar/Base.lua`), which is hostile to packages whose root dir
---name literally contains dots (`Nar.Base/`). A package init.lua is
---side-effect-only (registers natives); there is no semantic need to
---cache it in `package.loaded`.
---@param rt Runtime
---@param roots string[]
---@return string|nil err
local function registerPackageNatives(rt, roots)
    for _, root in ipairs(roots) do
        local initPath = root .. "/init.lua"
        local chunk, lerr = loadfile(initPath)
        if chunk == nil then
            -- Distinguish "file does not exist" (silently skip) from a real
            -- load error.
            local f = io.open(initPath, "rb")
            if f == nil then
                -- no init.lua → nothing to register for this package
            else
                f:close()
                return "load " .. initPath .. ": " .. tostring(lerr)
            end
        else
            local cok, modOrErr = pcall(chunk)
            if not cok then
                return "evaluate " .. initPath .. ": " .. tostring(modOrErr)
            end
            if type(modOrErr) ~= "function" then
                return initPath .. " must `return function(rt) ... end`" ..
                    " (got " .. type(modOrErr) .. ")"
            end
            local rok, rerr = pcall(modOrErr, rt)
            if not rok then
                return "register natives from " .. initPath .. ": " .. tostring(rerr)
            end
        end
    end
    return nil
end

---Build a Nar `List String` Object from a Lua array of strings.
---@param strs string[]
---@return table
local function makeStringListObject(strs)
    local items = {}
    for i, s in ipairs(strs) do
        items[i] = Object.makeString(s)
    end
    return Object.makeList(items)
end

---Execute `entryName` on the bytecode, with `scriptArgs` as a List String.
---@param bytes string
---@param pkgRoots string[]
---@param entryName string
---@param scriptArgs string[]
---@return integer exitCode
local function runProgram(bytes, pkgRoots, entryName, scriptArgs)
    local btc = Runtime.loadBytecode(bytes)
    local rt = Runtime.new(btc)

    local nerr = registerPackageNatives(rt, pkgRoots)
    if nerr ~= nil then
        eprintln("lunar: " .. nerr)
        return 1
    end

    if (rt.program.exports or {})[entryName] == nil then
        eprintln("lunar: entry `" .. entryName ..
            "` is not exported by the compiled bytecode")
        return 1
    end

    local argsList = makeStringListObject(scriptArgs)
    local result, rerr = rt:apply(entryName, { argsList })
    if rerr ~= nil then
        eprintln("lunar: " .. tostring(rerr))
        return 1
    end
    if result == nil then
        eprintln("lunar: entry `" .. entryName .. "` returned nil")
        return 1
    end

    local okCode, codeOrErr = pcall(Object.toInt, rt, result)
    if not okCode then
        eprintln("lunar: entry `" .. entryName ..
            "` must return Int (got " .. tostring(codeOrErr) .. ")")
        return 1
    end
    return math.floor(codeOrErr)
end

-- ----------------------------------------------------------------------------
-- main
-- ----------------------------------------------------------------------------

---@param argv string[]
---@return integer exitCode
local function main(argv)
    if argv == nil or #argv == 0 then
        usage()
        return 2
    end

    local preArgs, scriptArgs = splitOnDoubleDash(argv)

    local debug = false
    local outPath = nil
    local runEntry = nil
    local positional = {}

    local i = 1
    while i <= #preArgs do
        local a = preArgs[i]
        if a == "--debug" then
            debug = true
        elseif a == "--out" then
            if i == #preArgs then
                eprintln("lunar: --out requires a FILE argument")
                return 2
            end
            i = i + 1
            outPath = preArgs[i]
        elseif a == "--run" then
            if i == #preArgs then
                eprintln("lunar: --run requires a MOD.DEF argument")
                return 2
            end
            i = i + 1
            runEntry = preArgs[i]
        elseif a == "-h" or a == "--help" then
            usage()
            return 0
        elseif a:sub(1, 1) == "-" then
            eprintln("lunar: unknown flag `" .. a .. "`")
            return 2
        else
            positional[#positional + 1] = a
        end
        i = i + 1
    end

    if #scriptArgs > 0 and runEntry == nil then
        eprintln("lunar: arguments after `--` require `--run MOD.DEF`")
        return 2
    end

    if #positional == 0 then
        eprintln("lunar: at least one source file or glob is required")
        eprintln("try `lunar --help`")
        return 2
    end

    local files, ferr = collectSources(positional)
    if files == nil then
        eprintln(ferr)
        return 2
    end

    local sources, serr = readSources(files)
    if sources == nil then
        eprintln(serr)
        return 1
    end

    local bytes, errors = Compiler.compile(sources, debug)
    if errors ~= nil and #errors > 0 then
        for _, e in ipairs(errors) do
            eprintln(tostring(e))
        end
    end
    if bytes == nil then
        return 1
    end

    -- Decide whether to write the bytecode file.
    --   * No --run            → always write (default path = program.binar).
    --   * --run + --out FILE  → write FILE *and* run.
    --   * --run alone         → in-memory only, skip writing.
    local effectiveOut = outPath
    if effectiveOut == nil and runEntry == nil then
        effectiveOut = "program.binar"
    end

    if effectiveOut ~= nil then
        local ok, werr = writeAll(effectiveOut, bytes)
        if not ok then
            eprintln("lunar: write " .. effectiveOut .. ": " .. tostring(werr))
            return 1
        end
        io.write(string.format("lunar: wrote %s (%d bytes, %d modules)\n",
            effectiveOut, #bytes, #files))
    end

    if runEntry == nil then
        return 0
    end

    return runProgram(bytes, discoverPackageRoots(files), runEntry, scriptArgs)
end

if _IS_MAIN then
    os.exit(main(arg) or 0)
end

return { main = main }
