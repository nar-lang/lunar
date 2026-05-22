---`lunar build` — compile Nar sources to a single bytecode file.
---
---Usage: `lunar build [--debug] [--out FILE] <file-or-glob>...`
---
---Positional arguments accept:
---  - an exact `.nar` file path;
---  - `<dir>/*`     — every `.nar` file directly under `<dir>`;
---  - `<dir>/**/*`  — every `.nar` file recursively under `<dir>`.
---
---Flags:
---  --debug         emit debug info into the bytecode
---  --out FILE      output path (default: `program.binar`)

local Compiler = require("lunar.compiler")
local Common   = require("lunar.cli._common")

local M = {}

local function printHelp()
    io.write([[
usage: lunar build [--debug] [--out FILE] <file-or-glob>...

Compile Nar sources to a single bytecode file.

Positional arguments:
  <file.nar>      a single source file
  <dir>/*         every .nar file directly under <dir>
  <dir>/**/*      every .nar file recursively under <dir>

Flags:
  --debug         emit debug info into the bytecode
  --out FILE      output path (default: program.binar)
  -h, --help      show this help
]])
end

---@param args string[]
---@return integer  exitCode
function M.run(args)
    local debug = false
    local outPath = "program.binar"
    local positional = {}

    local i = 1
    while i <= #args do
        local a = args[i]
        if a == "--debug" then
            debug = true
        elseif a == "--out" then
            if i == #args then
                Common.eprintln("lunar build: --out requires a FILE argument")
                return 2
            end
            i = i + 1
            outPath = args[i]
        elseif a == "-h" or a == "--help" then
            printHelp()
            return 0
        elseif a:sub(1, 1) == "-" then
            Common.eprintln("lunar build: unknown flag `" .. a .. "`")
            return 2
        else
            positional[#positional + 1] = a
        end
        i = i + 1
    end

    if #positional == 0 then
        Common.eprintln("lunar build: at least one source file or glob is required")
        Common.eprintln("try `lunar build --help`")
        return 2
    end

    local files, ferr = Common.collectSources("lunar build", positional)
    if files == nil then
        Common.eprintln(ferr)
        return 2
    end

    local sources, serr = Common.readSources("lunar build", files)
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

    local ok, werr = Common.writeAll(outPath, bytes)
    if not ok then
        Common.eprintln("lunar build: write " .. outPath .. ": " .. tostring(werr))
        return 1
    end

    io.write(string.format("lunar build: wrote %s (%d bytes, %d modules)\n",
        outPath, #bytes, #files))
    return 0
end

return M
