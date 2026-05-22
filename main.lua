---Lunar CLI entry point.
---
---Usage: `lunar <verb> [args...]`. Run via the `bin/lunar` wrapper (which
---sets up `LUA_PATH` so that `require("lunar.*")` resolves), or directly
---with `lua lunar/main.lua ...` if `package.path` already includes the
---parent of the `lunar/` directory.
---
---Each verb lives in `lunar.cli.<verb>` and exposes `run(args) -> exitCode`.

local function usage()
    io.stderr:write([[
usage: lunar <verb> [args...]

verbs:
  build    Compile Nar sources to bytecode
  run      Compile and execute the entry definition

See `lunar <verb> --help` for verb-specific usage.
]])
end

if arg == nil or #arg == 0 then
    usage()
    os.exit(2)
end

local verb = arg[1]
local verbArgs = {}
for i = 2, #arg do
    verbArgs[#verbArgs + 1] = arg[i]
end

local ok, verbMod = pcall(require, "lunar.cli." .. verb)
if not ok then
    io.stderr:write("lunar: unknown verb `" .. verb .. "`\n")
    usage()
    os.exit(2)
end

if type(verbMod) ~= "table" or type(verbMod.run) ~= "function" then
    io.stderr:write("lunar: verb `" .. verb .. "` is missing a run(args) function\n")
    os.exit(2)
end

os.exit(verbMod.run(verbArgs) or 0)
