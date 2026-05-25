#!/usr/bin/env lua
---Lunar CLI.
---
---Usage: `lunar [--debug] [--bin FILE] [--run MOD.DEF] [--cache PATH] [--package PATH]... [--native PATH]... [<file-or-glob>...] [-- <script-args>...]`
---
---At least one of `--bin` or `--run` is required.
---
---When source files are given they are compiled. The resulting bytecode is
---written to `--bin FILE` if provided; if only `--run` is given, the
---bytecode is written to a temporary file that is deleted after the run
---completes.
---
---With `--run MOD.DEF`, the compiled (or pre-existing) bytecode is loaded
---into an in-process runtime and the given entry is executed. The entry
---must have type `(args: List String) -> Int`. Arguments after a literal
---`--` are passed as the `List String`; the returned `Int` is the
---process exit code.
---
---When no source files (positional or via `--package`) are given, both
---`--bin` and `--run` are required: the bytecode is loaded from `--bin`
---and executed directly without any compilation step.
---
---Positional arguments accept:
---  * an exact `.nar` file path;
---  * `<dir>/*`     — every `.nar` file directly under `<dir>`;
---  * `<dir>/**/*`  — every `.nar` file recursively under `<dir>`.
---
---Packages: `--package PATH` is the high-level way to add a whole Nar
---package to the build. PATH must be a directory containing a `nar.json`
---manifest. Every `*.nar` file found recursively under it is added as a
---source module, and if `PATH/init.lua` exists, that file is
---automatically registered as a native module (equivalent to passing
---`--native PATH/init.lua`). `--package` may be given multiple times.
---
---Dependencies declared in each package's `nar.json` are resolved
---recursively. Each dependency entry has the form
---`"<name>": "<repository>"`. If a dependency's `<name>` matches the
---declared name of another `--package`, that user-provided package is
---used; otherwise the repository is cloned (with `git clone --depth 1`)
---into `<cache>/<repository>` and its own dependencies are resolved in
---turn. The cache directory defaults to `~/.nar` and is controlled by
---`--cache PATH`.
---
---Native registration is explicit: pass `--native PATH` once per Lua
---module that should be loaded into the runtime before `--run` executes.
---PATH may be either a `.lua` file or a directory (in which case
---`/init.lua` is appended). Each module must `return function(rt) ... end`
---and will be invoked with the live `Runtime` so it can call
---`rt:registerDef(...)`. `--native` is required only when running
---(`--run`) code that depends on native definitions.

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

---True if `path` exists and is a directory, false otherwise.
---@param path string
---@return boolean
local function isDir(path)
    -- Open-the-dir trick: io.open on a directory succeeds on Linux but
    -- fails on macOS, so use a shell `[ -d ... ]` for portability.
    local cmd = 'test -d "' .. path:gsub('"', '\\"') .. '" && echo y || echo n'
    local p = io.popen(cmd)
    if p == nil then return false end
    local r = p:read("*l")
    p:close()
    return r == "y"
end

---True if `path` exists and is a regular file, false otherwise.
---@param path string
---@return boolean
local function isFile(path)
    local f = io.open(path, "rb")
    if f == nil then return false end
    f:close()
    return true
end

---Expand a leading `~` (referring to `$HOME`) in a path. Leaves other
---paths unchanged. If `$HOME` is unset the original path is returned.
---@param path string
---@return string
local function expandHome(path)
    if path == "~" then
        return os.getenv("HOME") or path
    end
    if path:sub(1, 2) == "~/" then
        local home = os.getenv("HOME")
        if home == nil then return path end
        return home .. path:sub(2)
    end
    return path
end

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

-- ----------------------------------------------------------------------------
-- Minimal JSON parser
-- ----------------------------------------------------------------------------
-- Recursive-descent parser for the strict subset of JSON used by nar.json
-- (strings, numbers, booleans, null, arrays, objects). Returns the parsed
-- value or `nil, err`. Object keys preserve no ordering guarantee.

---@param text string
---@return any|nil value, string|nil err
local function jsonParse(text)
    local i = 1
    local n = #text

    local skipWs, parseValue, parseString, parseArray, parseObject, parseNumber

    skipWs = function()
        while i <= n do
            local c = text:sub(i, i)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                i = i + 1
            else
                return
            end
        end
    end

    local function err(msg)
        error("at offset " .. i .. ": " .. msg, 0)
    end

    parseString = function()
        if text:sub(i, i) ~= '"' then err("expected string") end
        i = i + 1
        local out = {}
        while i <= n do
            local c = text:sub(i, i)
            if c == '"' then
                i = i + 1
                return table.concat(out)
            elseif c == "\\" then
                i = i + 1
                local esc = text:sub(i, i)
                i = i + 1
                if esc == '"' then out[#out + 1] = '"'
                elseif esc == '\\' then out[#out + 1] = '\\'
                elseif esc == '/' then out[#out + 1] = '/'
                elseif esc == 'n' then out[#out + 1] = '\n'
                elseif esc == 't' then out[#out + 1] = '\t'
                elseif esc == 'r' then out[#out + 1] = '\r'
                elseif esc == 'b' then out[#out + 1] = '\b'
                elseif esc == 'f' then out[#out + 1] = '\f'
                elseif esc == 'u' then
                    local cp = tonumber(text:sub(i, i + 3), 16)
                    if cp == nil then err("bad \\u escape") end
                    i = i + 4
                    out[#out + 1] = utf8.char(cp)
                else err("bad escape \\" .. esc) end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        err("unterminated string")
    end

    parseArray = function()
        i = i + 1
        skipWs()
        local arr = {}
        if text:sub(i, i) == "]" then i = i + 1; return arr end
        while true do
            arr[#arr + 1] = parseValue()
            skipWs()
            local c = text:sub(i, i)
            if c == "," then i = i + 1; skipWs()
            elseif c == "]" then i = i + 1; return arr
            else err("expected , or ]") end
        end
    end

    parseObject = function()
        i = i + 1
        skipWs()
        local obj = {}
        if text:sub(i, i) == "}" then i = i + 1; return obj end
        while true do
            skipWs()
            local key = parseString()
            skipWs()
            if text:sub(i, i) ~= ":" then err("expected :") end
            i = i + 1
            skipWs()
            obj[key] = parseValue()
            skipWs()
            local c = text:sub(i, i)
            if c == "," then i = i + 1
            elseif c == "}" then i = i + 1; return obj
            else err("expected , or }") end
        end
    end

    parseNumber = function()
        local s = i
        if text:sub(i, i) == "-" then i = i + 1 end
        while i <= n and text:sub(i, i):match("[%d%.eE%+%-]") do
            i = i + 1
        end
        local num = tonumber(text:sub(s, i - 1))
        if num == nil then err("bad number") end
        return num
    end

    parseValue = function()
        skipWs()
        local c = text:sub(i, i)
        if c == '"' then return parseString() end
        if c == "{" then return parseObject() end
        if c == "[" then return parseArray() end
        if c == "t" then
            if text:sub(i, i + 3) ~= "true" then err("expected true") end
            i = i + 4; return true
        end
        if c == "f" then
            if text:sub(i, i + 4) ~= "false" then err("expected false") end
            i = i + 5; return false
        end
        if c == "n" then
            if text:sub(i, i + 3) ~= "null" then err("expected null") end
            i = i + 4; return nil
        end
        if c == "-" or (c >= "0" and c <= "9") then return parseNumber() end
        err("unexpected character `" .. c .. "`")
    end

    local ok, result = pcall(parseValue)
    if not ok then
        return nil, tostring(result)
    end
    return result
end

-- ----------------------------------------------------------------------------
-- Package descriptor loader & dependency resolver
-- ----------------------------------------------------------------------------

---@class PackageInfo
---@field name string         declared package name from nar.json
---@field repository string   canonical repo URL (e.g. github.com/.../X)
---@field dependencies table<string,string>  alias -> repo URL
---@field path string         absolute or workspace-relative directory
---@field sources string[]    every *.nar file under `path` (recursive)
---@field nativePath string|nil   path/init.lua if it exists

---Read `<dir>/nar.json` and return a PackageInfo. Sources and nativePath
---are populated immediately so the caller can iterate without re-walking.
---@param dir string
---@return PackageInfo|nil info, string|nil err
local function loadPackageInfo(dir)
    if not isDir(dir) then
        return nil, "not a directory: " .. dir
    end
    local manifestPath = dir .. "/nar.json"
    local text, rerr = readAll(manifestPath)
    if text == nil then
        return nil, "read " .. manifestPath .. ": " .. tostring(rerr)
    end
    local parsed, perr = jsonParse(text)
    if parsed == nil then
        return nil, "parse " .. manifestPath .. ": " .. tostring(perr)
    end
    if type(parsed) ~= "table" then
        return nil, manifestPath .. ": root must be an object"
    end
    local name = parsed.name
    if type(name) ~= "string" or name == "" then
        return nil, manifestPath .. ": missing or invalid `name` (string)"
    end
    local repo = parsed.repository
    if repo ~= nil and type(repo) ~= "string" then
        return nil, manifestPath .. ": invalid `repository` (must be string)"
    end
    local deps = parsed.dependencies
    if deps == nil then
        deps = {}
    elseif type(deps) ~= "table" then
        return nil, manifestPath .. ": `dependencies` must be an object"
    end
    -- Reject the old array form explicitly so the schema migration is clear.
    if #deps > 0 then
        return nil, manifestPath ..
            ": `dependencies` must be {name: repository} (got array)"
    end
    for k, v in pairs(deps) do
        if type(k) ~= "string" or type(v) ~= "string" then
            return nil, manifestPath ..
                ": `dependencies` entries must be string -> string"
        end
    end

    local quoted = dir:gsub('"', '\\"')
    local sources = findLines('find "' .. quoted .. '" -type f -name "*.nar" 2>/dev/null')

    local nativePath = nil
    local initLua = dir .. "/init.lua"
    if isFile(initLua) then
        nativePath = initLua
    end

    return {
        name = name,
        repository = repo or "",
        dependencies = deps,
        path = dir,
        sources = sources,
        nativePath = nativePath,
    }
end

---Clone `repoUrl` into `destDir`. Uses `git clone --depth 1 https://<repoUrl>`.
---Creates parent directories as needed. Returns nil on success or an error
---string on failure.
---@param repoUrl string  e.g. github.com/nar-lang/Nar.Base
---@param destDir string
---@return string|nil err
local function cloneRepo(repoUrl, destDir)
    -- mkdir -p the parent so `git clone` can land into a fresh leaf.
    local parent = dirname(destDir)
    if parent ~= "" then
        os.execute('mkdir -p "' .. parent:gsub('"', '\\"') .. '"')
    end
    local quotedUrl = repoUrl:gsub('"', '\\"')
    local quotedDest = destDir:gsub('"', '\\"')
    eprintln("lunar: cloning " .. repoUrl .. " -> " .. destDir)
    local cmd = 'git clone --depth 1 "https://' .. quotedUrl .. '" "' ..
        quotedDest .. '" >&2'
    local ok = os.execute(cmd)
    if ok ~= true and ok ~= 0 then
        return "git clone failed for " .. repoUrl
    end
    return nil
end

---Resolve all transitive dependencies starting from `rootPaths`. Packages
---whose `name` matches one of the roots are preferred; missing deps are
---cloned into `<cachePath>/<repository>`. Returns an ordered list with
---dependencies appearing before their dependents.
---@param rootPaths string[]
---@param cachePath string
---@return PackageInfo[]|nil ordered, string|nil err
local function resolvePackages(rootPaths, cachePath)
    -- Load every root first so we know which names are user-provided.
    local roots = {}
    local providedByName = {}
    for _, p in ipairs(rootPaths) do
        local info, lerr = loadPackageInfo(p)
        if info == nil then
            return nil, lerr
        end
        if providedByName[info.name] ~= nil then
            return nil, "duplicate --package: two roots declare name `" ..
                info.name .. "` (" .. providedByName[info.name].path ..
                " and " .. info.path .. ")"
        end
        providedByName[info.name] = info
        roots[#roots + 1] = info
    end

    local visited = {}    -- name -> true once recorded
    local ordered = {}
    local resolveOne     -- forward decl

    resolveOne = function(info)
        if visited[info.name] then return nil end
        visited[info.name] = true
        for depName, depRepo in pairs(info.dependencies) do
            local depInfo = providedByName[depName]
            if depInfo == nil then
                local destDir = cachePath .. "/" .. depRepo
                if not isDir(destDir) then
                    local cerr = cloneRepo(depRepo, destDir)
                    if cerr ~= nil then return cerr end
                end
                local loaded, lerr = loadPackageInfo(destDir)
                if loaded == nil then
                    return "dependency `" .. depName .. "` of `" .. info.name ..
                        "`: " .. lerr
                end
                if loaded.name ~= depName then
                    -- Soft warning is fine; mismatched alias vs declared name
                    -- still resolves topologically.
                    eprintln("lunar: warning: dependency alias `" .. depName ..
                        "` does not match declared name `" .. loaded.name ..
                        "` in " .. destDir .. "/nar.json")
                end
                providedByName[loaded.name] = loaded
                depInfo = loaded
            end
            local rerr = resolveOne(depInfo)
            if rerr ~= nil then return rerr end
        end
        ordered[#ordered + 1] = info
        return nil
    end

    for _, info in ipairs(roots) do
        local rerr = resolveOne(info)
        if rerr ~= nil then
            return nil, rerr
        end
    end

    return ordered
end

-- ----------------------------------------------------------------------------
-- Argument expansion (globs)
-- ----------------------------------------------------------------------------

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
usage: lunar [-d|--debug] [-b|--bin FILE] [-r|--run MOD.DEF]
             [-c|--cache PATH] [-p|--package PATH]... [-n|--native PATH]...
             [<file-or-glob>...] [-- <script-args>...]

Compile Nar sources and/or run a compiled program. At least one of
`--bin` or `--run` must be given.

Positional arguments (before `--`):
  <file.nar>      a single source file
  <dir>/*         every .nar file directly under <dir>
  <dir>/**/*      every .nar file recursively under <dir>

Flags (each long flag has a single-letter short alias):
  -d, --debug         emit debug info into the bytecode
  -b, --bin FILE      bytecode file path. With sources, the compiled
                      bytecode is written here. Without sources, the
                      bytecode is loaded from here (no compilation).
  -r, --run MOD.DEF   execute the given entry in an in-process runtime.
                      The entry must have type
                      `(args: List String) -> Int`. Arguments after `--`
                      become the List String; the returned Int is the
                      process exit code.
  -c, --cache PATH    directory used to cache cloned dependencies.
                      Defaults to ~/.nar.
  -p, --package PATH  add an entire Nar package to the build. PATH must
                      be a directory containing a nar.json manifest.
                      Every *.nar file recursively under it is added as
                      a source module, and if PATH/init.lua exists it is
                      registered as a native module. Transitive deps
                      declared in nar.json are resolved automatically:
                      deps whose name matches another --package are used
                      from there; otherwise the repository is cloned
                      into <cache>/<repository>. May be given multiple
                      times.
  -n, --native PATH   register a native Lua module before running. PATH
                      is either a .lua file or a directory (in which
                      case /init.lua is appended). The module must
                      `return function(rt) ... end`. May be given
                      multiple times; modules are loaded in the order
                      specified.
  -h, --help          show this help

Behaviour summary:
  * sources/packages + --bin              compile, write FILE
  * sources/packages + --run              compile to a temp file, run, delete temp
  * sources/packages + --bin + --run      compile, write FILE, run
  * --bin + --run (no sources/packages)   load FILE, run (no compilation)
  * no --bin and no --run                 error

Examples:
  # Compile to program.binar
  lunar -b program.binar -p Nar.Base

  # Compile and run in one shot (no file is left on disk)
  lunar -r Hello.main -p Nar.Base Hello.nar -- one two three

  # Compile, persist bytecode, and run it
  lunar -b hello.binar -r Hello.main -p Nar.Base Hello.nar

  # Run a previously-compiled bytecode
  lunar -b hello.binar -r Hello.main -n Nar.Base -n Nar.Tests \
        -- one two three
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

---Resolve a `--native PATH` argument to the actual Lua file to load.
---If `PATH` is a directory, `/init.lua` is appended. Otherwise it is
---returned as-is.
---@param path string
---@return string
local function resolveNativePath(path)
    if isDir(path) then
        return path .. "/init.lua"
    end
    return path
end

---Build a unique temp path for a bytecode file. Uses `os.tmpname()` for
---uniqueness; we append `.binar` so the path is recognisable. The caller
---is responsible for removing the file after use.
---@return string
local function makeTempBinPath()
    local base = os.tmpname()
    return base .. ".binar"
end

---Load and apply each explicitly-listed native Lua module to the runtime.
---
---We use `loadfile` rather than `require` because Lua's require translates
---dots in the module name into path separators (so `require("Nar.Base")`
---looks for `Nar/Base.lua`), which is hostile to packages whose root dir
---name literally contains dots (`Nar.Base/`). Native modules are
---side-effect-only (they register definitions on `rt`); there is no
---semantic need to cache them in `package.loaded`.
---@param rt Runtime
---@param nativePaths string[] paths already resolved by `resolveNativePath`
---@return string|nil err
local function registerNatives(rt, nativePaths)
    for _, path in ipairs(nativePaths) do
        local chunk, lerr = loadfile(path)
        if chunk == nil then
            return "load " .. path .. ": " .. tostring(lerr)
        end
        local cok, modOrErr = pcall(chunk)
        if not cok then
            return "evaluate " .. path .. ": " .. tostring(modOrErr)
        end
        if type(modOrErr) ~= "function" then
            return path .. " must `return function(rt) ... end`" ..
                " (got " .. type(modOrErr) .. ")"
        end
        local rok, rerr = pcall(modOrErr, rt)
        if not rok then
            return "register natives from " .. path .. ": " .. tostring(rerr)
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
---@param nativePaths string[]
---@param entryName string
---@param scriptArgs string[]
---@return integer exitCode
local function runProgram(bytes, nativePaths, entryName, scriptArgs)
    local btc = Runtime.loadBytecode(bytes)
    local rt = Runtime.new(btc)

    local nerr = registerNatives(rt, nativePaths)
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
    local binPath = nil
    local runEntry = nil
    local cachePath = expandHome("~/.nar")
    local nativePaths = {}
    local packagePaths = {}
    local positional = {}
    local explicitNativeCount = 0

    local i = 1
    while i <= #preArgs do
        local a = preArgs[i]
        if a == "--debug" or a == "-d" then
            debug = true
        elseif a == "--bin" or a == "-b" then
            if i == #preArgs then
                eprintln("lunar: --bin requires a FILE argument")
                return 2
            end
            i = i + 1
            binPath = preArgs[i]
        elseif a == "--run" or a == "-r" then
            if i == #preArgs then
                eprintln("lunar: --run requires a MOD.DEF argument")
                return 2
            end
            i = i + 1
            runEntry = preArgs[i]
        elseif a == "--cache" or a == "-c" then
            if i == #preArgs then
                eprintln("lunar: --cache requires a PATH argument")
                return 2
            end
            i = i + 1
            cachePath = expandHome(preArgs[i])
        elseif a == "--package" or a == "-p" then
            if i == #preArgs then
                eprintln("lunar: --package requires a PATH argument")
                return 2
            end
            i = i + 1
            packagePaths[#packagePaths + 1] = preArgs[i]
        elseif a == "--native" or a == "-n" then
            if i == #preArgs then
                eprintln("lunar: --native requires a PATH argument")
                return 2
            end
            i = i + 1
            nativePaths[#nativePaths + 1] = resolveNativePath(preArgs[i])
            explicitNativeCount = explicitNativeCount + 1
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

    if explicitNativeCount > 0 and runEntry == nil then
        eprintln("lunar: --native is only meaningful together with --run")
        return 2
    end

    if binPath == nil and runEntry == nil then
        eprintln("lunar: at least one of --bin or --run is required")
        eprintln("try `lunar --help`")
        return 2
    end

    -- Resolve each --package and its transitive dependencies. Missing deps
    -- are cloned into `<cachePath>/<repository>`. Resolution returns the
    -- packages in dependency-first order. Auto-discovered native paths are
    -- appended AFTER explicit --native, so explicit registrations win when
    -- registration order matters.
    local packageSources = {}
    if #packagePaths > 0 then
        -- Ensure cache dir exists before any potential clone.
        os.execute('mkdir -p "' .. cachePath:gsub('"', '\\"') .. '"')
        local resolved, rerr = resolvePackages(packagePaths, cachePath)
        if resolved == nil then
            eprintln("lunar: " .. rerr)
            return 2
        end
        for _, info in ipairs(resolved) do
            for _, f in ipairs(info.sources) do
                packageSources[#packageSources + 1] = f
            end
            if info.nativePath ~= nil then
                nativePaths[#nativePaths + 1] = info.nativePath
            end
        end
    end

    -- ---- No-sources path: run the pre-existing binary, no compilation. ----
    if #positional == 0 and #packagePaths == 0 then
        if binPath == nil or runEntry == nil then
            eprintln("lunar: no source files; --bin and --run are both required" ..
                " to run an existing binary")
            return 2
        end
        local bytes, rerr = readAll(binPath)
        if bytes == nil then
            eprintln("lunar: read " .. binPath .. ": " .. tostring(rerr))
            return 1
        end
        return runProgram(bytes, nativePaths, runEntry, scriptArgs)
    end

    -- ---- Compile path. -----------------------------------------------------
    local files, ferr = collectSources(positional)
    if files == nil then
        eprintln(ferr)
        return 2
    end

    -- Merge in package-discovered sources (dedup by exact path).
    local seenFile = {}
    for _, f in ipairs(files) do seenFile[f] = true end
    for _, f in ipairs(packageSources) do
        if not seenFile[f] then
            seenFile[f] = true
            files[#files + 1] = f
        end
    end

    if #files == 0 then
        eprintln("lunar: no .nar source files to compile")
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

    -- Decide bytecode output location:
    --   * --bin FILE          → write FILE (and keep it).
    --   * --run only          → write temp file, delete after run.
    --   * --bin + --run       → write FILE (and keep it), then run.
    local writePath = binPath
    local tempPath = nil
    if writePath == nil then
        -- runEntry is guaranteed non-nil here (we errored above otherwise).
        tempPath = makeTempBinPath()
        writePath = tempPath
    end

    local ok, werr = writeAll(writePath, bytes)
    if not ok then
        eprintln("lunar: write " .. writePath .. ": " .. tostring(werr))
        if tempPath ~= nil then os.remove(tempPath) end
        return 1
    end
    if tempPath == nil then
        io.write(string.format("lunar: wrote %s (%d bytes, %d modules)\n",
            writePath, #bytes, #files))
    end

    if runEntry == nil then
        return 0
    end

    local exitCode = runProgram(bytes, nativePaths, runEntry, scriptArgs)
    if tempPath ~= nil then os.remove(tempPath) end
    return exitCode
end

if _IS_MAIN then
    os.exit(main(arg) or 0)
end

return { main = main }
