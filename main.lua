---Lunar CLI entry point.
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

local Compiler = require("lunar.compiler")
local Runtime  = require("lunar.runtime")
local Object   = Runtime.Object
local Common   = require("lunar.cli._common")

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
        local d = Common.dirname(path)
        if d == "" then d = "." end
        local root = Common.findPackageRoot(d, "nar.json")
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
        Common.eprintln("lunar: " .. nerr)
        return 1
    end

    if (rt.program.exports or {})[entryName] == nil then
        Common.eprintln("lunar: entry `" .. entryName ..
            "` is not exported by the compiled bytecode")
        return 1
    end

    local argsList = makeStringListObject(scriptArgs)
    local result, rerr = rt:apply(entryName, { argsList })
    if rerr ~= nil then
        Common.eprintln("lunar: " .. tostring(rerr))
        return 1
    end
    if result == nil then
        Common.eprintln("lunar: entry `" .. entryName .. "` returned nil")
        return 1
    end

    local okCode, codeOrErr = pcall(Object.toInt, rt, result)
    if not okCode then
        Common.eprintln("lunar: entry `" .. entryName ..
            "` must return Int (got " .. tostring(codeOrErr) .. ")")
        return 1
    end
    return math.floor(codeOrErr)
end

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
                Common.eprintln("lunar: --out requires a FILE argument")
                return 2
            end
            i = i + 1
            outPath = preArgs[i]
        elseif a == "--run" then
            if i == #preArgs then
                Common.eprintln("lunar: --run requires a MOD.DEF argument")
                return 2
            end
            i = i + 1
            runEntry = preArgs[i]
        elseif a == "-h" or a == "--help" then
            usage()
            return 0
        elseif a:sub(1, 1) == "-" then
            Common.eprintln("lunar: unknown flag `" .. a .. "`")
            return 2
        else
            positional[#positional + 1] = a
        end
        i = i + 1
    end

    if #scriptArgs > 0 and runEntry == nil then
        Common.eprintln("lunar: arguments after `--` require `--run MOD.DEF`")
        return 2
    end

    if #positional == 0 then
        Common.eprintln("lunar: at least one source file or glob is required")
        Common.eprintln("try `lunar --help`")
        return 2
    end

    local files, ferr = Common.collectSources("lunar", positional)
    if files == nil then
        Common.eprintln(ferr)
        return 2
    end

    local sources, serr = Common.readSources("lunar", files)
    if sources == nil then
        Common.eprintln(serr)
        return 1
    end

    local bytes, errors = Compiler.compile(sources, debug)
    if errors ~= nil and #errors > 0 then
        for _, e in ipairs(errors) do
            Common.eprintln(tostring(e))
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
        local ok, werr = Common.writeAll(effectiveOut, bytes)
        if not ok then
            Common.eprintln("lunar: write " .. effectiveOut .. ": " .. tostring(werr))
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

os.exit(main(arg) or 0)
