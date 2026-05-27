#!/usr/bin/env lua
---Lunar CLI.
---
---Usage: `lunar [--debug] [--bin FILE] [--run MOD.DEF] [--doc FILE] [--cache PATH] [--dir DIR]... [--package NAME]... [--native PATH]... [<file-or-glob>...] [-- <script-args>...]`
---
---At least one of `--bin`, `--run`, or `--doc` is required.
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
---Packages: `--package NAME` adds a whole Nar package (by declared
---`nar.json.name`) to the build. May be given multiple times. Each name
---is resolved against the search path:
---  1. the cache dir (`--cache PATH`, default `~/.nar`);
---  2. each `--dir DIR` in the order given (defaults to `.` if none).
---For each candidate `<searchDir>` the resolver probes
---`<searchDir>/<name>/nar.json` first, then — when recursing into
---transitive dependencies — `<searchDir>/<repository>/nar.json`. If
---neither is found, the dependency's repository is cloned
---(`git clone --depth 1 https://<repo>`) into `<cache>/<repository>`.
---Every `*.nar` file under a resolved package is added as a source
---module, and if `<package>/init.lua` exists it is automatically
---registered as a native module (equivalent to `--native <package>`).
---
---Native registration is explicit: pass `--native PATH` once per Lua
---module that should be loaded into the runtime before `--run` executes.
---PATH may be either a `.lua` file or a directory (in which case
---`/init.lua` is appended). Each module must `return function(rt) ... end`
---and will be invoked with the live `Runtime` so it can call
---`rt:registerDef(...)`. `--native` is required only when running
---(`--run`) code that depends on native definitions not provided by a
---resolved `--package`.

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
local Docs     = require("lunar.compiler.docs")
local Packages = require("lunar.compiler.packages")
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
-- Package resolution (disk + git loader for `Packages.collect`)
-- ----------------------------------------------------------------------------
-- `lunar.compiler.packages` is IO-free: it walks the dependency graph but
-- delegates every `name -> (modules, natives, nar.json text)` lookup to a
-- callback. The CLI supplies a filesystem-backed loader here that probes a
-- list of search dirs and clones missing repos into the first one (the
-- cache dir). `Packages.parseJson` is reused for the candidate-name peek
-- so the CLI doesn't carry its own JSON parser.

---Read a `nar.json`-bearing directory. Returns the inputs
---`Packages.collect` expects: `(moduleFiles, nativeScripts, narJsonText)`.
---`nativeScripts` is a single-element list pointing at `<dir>/init.lua`
---when present.
---@param dir string
---@return string[]|nil moduleFiles
---@return string[]|nil nativeScripts
---@return string|nil narJsonText
---@return string|nil err
local function loadPackageDir(dir)
    if not isDir(dir) then
        return nil, nil, nil, "not a directory: " .. dir
    end
    local manifestPath = dir .. "/nar.json"
    if not isFile(manifestPath) then
        return nil, nil, nil, "missing manifest: " .. manifestPath
    end
    local text, rerr = readAll(manifestPath)
    if text == nil then
        return nil, nil, nil, "read " .. manifestPath .. ": " .. tostring(rerr)
    end

    local quoted = dir:gsub('"', '\\"')
    local modules = findLines('find "' .. quoted .. '" -type f -name "*.nar" 2>/dev/null')

    local natives = {}
    if isFile(dir .. "/init.lua") then
        natives[1] = dir .. "/init.lua"
    end

    return modules, natives, text, nil
end

---Try a candidate directory: succeeds only if the directory exists,
---has a `nar.json`, and its declared name matches `expectedName`.
---Returns `(nil, nil, nil, nil)` when the candidate is absent or the
---declared name doesn't match (caller should keep probing). Returns a
---real `err` only on a load / parse failure.
---@param dir string
---@param expectedName string
---@return string[]|nil moduleFiles
---@return string[]|nil nativeScripts
---@return string|nil narJsonText
---@return string|nil err
local function tryLoadCandidate(dir, expectedName)
    if not isDir(dir) then return nil, nil, nil, nil end
    if not isFile(dir .. "/nar.json") then return nil, nil, nil, nil end
    local modules, natives, text, lerr = loadPackageDir(dir)
    if lerr ~= nil then return nil, nil, nil, lerr end
    local parsed, perr = Packages.parseJson(text)
    if parsed == nil then
        return nil, nil, nil, "parse " .. dir .. "/nar.json: " .. tostring(perr)
    end
    if type(parsed) ~= "table" or parsed.name ~= expectedName then
        eprintln("lunar: warning: " .. dir ..
            "/nar.json declares name `" .. tostring(parsed.name) ..
            "` but was looked up as `" .. expectedName .. "`")
        return nil, nil, nil, nil
    end
    return modules, natives, text, nil
end

---@param repoUrl string e.g. github.com/nar-lang/Nar.Base
---@param destDir string
---@return string|nil err
local function cloneRepo(repoUrl, destDir)
    local parent = dirname(destDir)
    if parent ~= "" then
        os.execute('mkdir -p "' .. parent:gsub('"', '\\"') .. '"')
    end
    local quotedUrl  = repoUrl:gsub('"', '\\"')
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

---Build a `loadPackage(name, url)` closure suitable for
---`Packages.collect`. The closure probes every dir in `searchDirs` for
---`<dir>/<name>` first, then `<dir>/<url>` (if url is given), and
---falls back to `git clone https://<url>` into `searchDirs[1]/<url>`.
---@param searchDirs string[]  the first entry is also the clone cache dir
---@return LoadPackageFn
local function makeDiskLoader(searchDirs)
    assert(type(searchDirs) == "table" and #searchDirs > 0,
        "makeDiskLoader: searchDirs must be a non-empty list")
    local cacheDir = searchDirs[1]
    os.execute('mkdir -p "' .. cacheDir:gsub('"', '\\"') .. '"')

    return function(name, url)
        -- 1) by package name in each search dir
        for _, base in ipairs(searchDirs) do
            local m, n, t, lerr = tryLoadCandidate(base .. "/" .. name, name)
            if lerr ~= nil then return nil, nil, nil, lerr end
            if t ~= nil then return m, n, t, nil end
        end

        -- 2) by repo URL in each search dir
        if url ~= nil and url ~= "" then
            for _, base in ipairs(searchDirs) do
                local m, n, t, lerr = tryLoadCandidate(base .. "/" .. url, name)
                if lerr ~= nil then return nil, nil, nil, lerr end
                if t ~= nil then return m, n, t, nil end
            end

            -- 3) clone into the cache dir
            local destDir = cacheDir .. "/" .. url
            local cerr = cloneRepo(url, destDir)
            if cerr ~= nil then return nil, nil, nil, cerr end
            -- Name-mismatch warning happens in collect after parsing.
            return loadPackageDir(destDir)
        end

        return nil, nil, nil,
            "not found in search dirs (no repository URL to clone from)"
    end
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
usage: lunar [-d|--debug] [-b|--bin FILE] [-r|--run MOD.DEF] [--doc FILE]
             [-c|--cache PATH] [-D|--dir DIR]... [-p|--package NAME]...
             [-n|--native PATH]... [<file-or-glob>...] [-- <script-args>...]

Compile Nar sources and/or run a compiled program. At least one of
`--bin`, `--run`, or `--doc` must be given.

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
      --doc FILE      collect top-level `///`/`/** **/` doc comments
                      from the resolved sources and write a single
                      Markdown file (with TOC and per-module sections)
                      to FILE. Compilation must succeed first.
  -c, --cache PATH    directory used to cache cloned dependencies and
                      probed first when resolving packages by name or
                      repository. Defaults to ~/.nar.
  -D, --dir DIR       extra directory to probe when resolving --package
                      entries. May be given multiple times; if none are
                      given, `.` is used. The cache dir is always tried
                      first, then each --dir in order.
  -p, --package NAME  add a Nar package (by its declared `nar.json.name`)
                      to the build. For each NAME the resolver probes
                      `<dir>/<NAME>/nar.json` in turn across the search
                      path (cache dir + --dir entries). Transitive deps
                      declared in nar.json are resolved by name first,
                      then by repository path, and finally by cloning
                      `https://<repository>` into `<cache>/<repository>`.
                      Every *.nar file under a resolved package is added
                      as source; if `<package>/init.lua` exists it is
                      registered as a native module. May be given
                      multiple times.
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
  # Compile to program.binar, finding Nar.Base in the current dir
  lunar -b program.binar -p Nar.Base

  # Compile and run in one shot (no file is left on disk)
  lunar -r Hello.main -D ./packages -p Nar.Base Hello.nar -- one two three

  # Compile, persist bytecode, and run it
  lunar -b hello.binar -r Hello.main -D ./packages -p Nar.Base Hello.nar

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

    -- `--lsp` short-circuits the normal compile/run pipeline: when set
    -- we hand off to the JSON-RPC server loop and never return.
    for _, a in ipairs(preArgs) do
        if a == "--lsp" then
            local Lsp = require("lunar.lsp")
            Lsp.run()
            return 0
        end
    end

    local debug = false
    local binPath = nil
    local runEntry = nil
    local docPath = nil
    local cachePath = expandHome("~/.nar")
    local nativePaths = {}
    local packageNames = {}
    local searchDirs = {}
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
        elseif a == "--doc" then
            if i == #preArgs then
                eprintln("lunar: --doc requires a FILE argument")
                return 2
            end
            i = i + 1
            docPath = preArgs[i]
        elseif a == "--cache" or a == "-c" then
            if i == #preArgs then
                eprintln("lunar: --cache requires a PATH argument")
                return 2
            end
            i = i + 1
            cachePath = expandHome(preArgs[i])
        elseif a == "--dir" or a == "-D" then
            if i == #preArgs then
                eprintln("lunar: --dir requires a DIR argument")
                return 2
            end
            i = i + 1
            searchDirs[#searchDirs + 1] = expandHome(preArgs[i])
        elseif a == "--package" or a == "-p" then
            if i == #preArgs then
                eprintln("lunar: --package requires a NAME argument")
                return 2
            end
            i = i + 1
            packageNames[#packageNames + 1] = preArgs[i]
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

    if binPath == nil and runEntry == nil and docPath == nil then
        eprintln("lunar: at least one of --bin, --run, or --doc is required")
        eprintln("try `lunar --help`")
        return 2
    end

    -- Resolve each --package and its transitive dependencies. The CLI
    -- builds a disk-backed loader closure (probes cache dir + --dir
    -- entries, clones missing deps) and hands it to the pure resolver
    -- in `lunar.compiler.packages`. Native scripts returned by the
    -- loader are full paths to `.lua` files (typically
    -- `<pkgDir>/init.lua`) and are appended AFTER explicit --native,
    -- so explicit registrations win when registration order matters.
    local packageSources = {}
    if #packageNames > 0 then
        if #searchDirs == 0 then
            searchDirs[1] = "."
        end
        local fullSearch = { cachePath }
        for _, d in ipairs(searchDirs) do
            fullSearch[#fullSearch + 1] = d
        end
        local modules, natives, rerr =
            Packages.collect(packageNames, makeDiskLoader(fullSearch))
        if modules == nil then
            eprintln("lunar: " .. rerr)
            return 2
        end
        for _, f in ipairs(modules) do
            packageSources[#packageSources + 1] = f
        end
        for _, n in ipairs(natives) do
            nativePaths[#nativePaths + 1] = n
        end
    end

    -- ---- No-sources path: run the pre-existing binary, no compilation. ----
    if #positional == 0 and #packageNames == 0 then
        if docPath ~= nil then
            eprintln("lunar: --doc requires source files or a --package")
            return 2
        end
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

    -- ---- Documentation generation (optional). -------------------------
    if docPath ~= nil then
        -- Re-parse to obtain ParsedModule values; normalization strips
        -- doc-comment metadata so it isn't available off the compiled
        -- bytecode. Parsing is cheap and gives us the unprocessed AST.
        local parsedModules = {}
        local parseErrs = {}
        for name, content in pairs(sources) do
            local m, perr = Compiler.parse(name, content)
            if perr ~= nil then
                for _, e in ipairs(perr) do
                    parseErrs[#parseErrs + 1] = e
                end
            end
            if m ~= nil then
                parsedModules[m.name] = m
            end
        end
        if #parseErrs > 0 then
            for _, e in ipairs(parseErrs) do eprintln(tostring(e)) end
            return 1
        end
        local docPackageName = packageNames[1]
        local md = Docs.render(Docs.collect(parsedModules), docPackageName)
        local okw, werr = writeAll(docPath, md)
        if not okw then
            eprintln("lunar: write " .. docPath .. ": " .. tostring(werr))
            return 1
        end
        io.write(string.format("lunar: wrote %s (%d bytes)\n",
            docPath, #md))
    end

    -- If only --doc was requested, we're done.
    if binPath == nil and runEntry == nil then
        return 0
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
