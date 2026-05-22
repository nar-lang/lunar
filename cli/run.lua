---`lunar run` — compile Nar sources, register package natives, execute entry.
---
---Usage: `lunar run [--debug] [--entry MOD.DEF] <file-or-glob>... [-- <script-args>...]`
---
---Anything after a literal `--` is forwarded verbatim to the Nar program as
---a `List String` argument. The entry def must have type
---`(args: List String): Int`; its returned `Int` becomes the process exit
---code.
---
---Entry resolution: if `--entry MOD.DEF` is supplied, that fully-qualified
---export is used. Otherwise the runtime is scanned for exports ending in
---`.main`; if exactly one is found it is used, otherwise an error lists
---the candidates and asks for `--entry`.
---
---For every source file we walk up to the nearest directory containing
---`nar.json` (the package root). If that directory has an `init.lua`, it
---is required and called with the `Runtime` instance so it can register
---its native implementations.

local Compiler = require("lunar.compiler")
local Runtime  = require("lunar.runtime")
local Object   = Runtime.Object
local Common   = require("lunar.cli._common")

local M = {}

local function printHelp()
    io.write([[
usage: lunar run [--debug] [--entry MOD.DEF] <file-or-glob>... [-- <script-args>...]

Compile Nar sources and execute the entry definition.

The entry def must have type `(args: List String): Int`. The returned
`Int` is used as the process exit code.

If `--entry` is not given, the runtime is scanned for exports ending in
`.main`; if exactly one is found it is used, otherwise the candidates
are listed and you must pass `--entry MOD.DEF`.

Positional arguments (before `--`):
  <file.nar>      a single source file
  <dir>/*         every .nar file directly under <dir>
  <dir>/**/*      every .nar file recursively under <dir>

Flags:
  --debug         emit debug info into the bytecode
  --entry NAME    fully-qualified entry name (e.g. `My.App.main`)
  -h, --help      show this help

Use `--` to separate the source list from arguments passed to the Nar
program:

  lunar run my.nar pkg/* -- hello world
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

---Resolve which export to call as the program entry.
---@param rt Runtime
---@param explicit string|nil  e.g. "Hello.main"
---@return string|nil entry, string|nil err
local function resolveEntry(rt, explicit)
    local exports = rt.program.exports or {}
    if explicit ~= nil then
        if exports[explicit] == nil then
            return nil, "entry `" .. explicit .. "` is not exported by the bytecode"
        end
        return explicit
    end

    local candidates = {}
    for name in pairs(exports) do
        if name:match("%.main$") then
            candidates[#candidates + 1] = name
        end
    end
    if #candidates == 0 then
        return nil, "no `*.main` export found; pass `--entry MOD.DEF`"
    end
    if #candidates > 1 then
        table.sort(candidates)
        return nil, "multiple `*.main` exports found, pass `--entry MOD.DEF`:\n  - " ..
            table.concat(candidates, "\n  - ")
    end
    return candidates[1]
end

---@param args string[]
---@return integer exitCode
function M.run(args)
    local preArgs, scriptArgs = splitOnDoubleDash(args)

    local debug = false
    local explicitEntry = nil
    local positional = {}

    local i = 1
    while i <= #preArgs do
        local a = preArgs[i]
        if a == "--debug" then
            debug = true
        elseif a == "--entry" then
            if i == #preArgs then
                Common.eprintln("lunar run: --entry requires a NAME argument")
                return 2
            end
            i = i + 1
            explicitEntry = preArgs[i]
        elseif a == "-h" or a == "--help" then
            printHelp()
            return 0
        elseif a:sub(1, 1) == "-" then
            Common.eprintln("lunar run: unknown flag `" .. a .. "`")
            return 2
        else
            positional[#positional + 1] = a
        end
        i = i + 1
    end

    if #positional == 0 then
        Common.eprintln("lunar run: at least one source file or glob is required")
        Common.eprintln("try `lunar run --help`")
        return 2
    end

    local files, ferr = Common.collectSources("lunar run", positional)
    if files == nil then
        Common.eprintln(ferr)
        return 2
    end

    local sources, serr = Common.readSources("lunar run", files)
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

    local btc = Runtime.loadBytecode(bytes)
    local rt = Runtime.new(btc)

    local pkgRoots = discoverPackageRoots(files)
    local nerr = registerPackageNatives(rt, pkgRoots)
    if nerr ~= nil then
        Common.eprintln("lunar run: " .. nerr)
        return 1
    end

    local entry, eerr = resolveEntry(rt, explicitEntry)
    if entry == nil then
        Common.eprintln("lunar run: " .. eerr)
        return 1
    end

    local argsList = makeStringListObject(scriptArgs)
    local result, rerr = rt:apply(entry, { argsList })
    if rerr ~= nil then
        Common.eprintln("lunar run: " .. tostring(rerr))
        return 1
    end
    if result == nil then
        Common.eprintln("lunar run: entry `" .. entry .. "` returned nil")
        return 1
    end

    local okCode, codeOrErr = pcall(Object.toInt, rt, result)
    if not okCode then
        Common.eprintln("lunar run: entry `" .. entry ..
            "` must return Int (got " .. tostring(codeOrErr) .. ")")
        return 1
    end
    return math.floor(codeOrErr)
end

return M
