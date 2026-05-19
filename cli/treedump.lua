-- Tree dump CLI: walks one or more directories, parses every *.nar file
-- with compiler.parser and writes the parsed AST tree (via
-- module:stringTree(0)) to <file>.tree.lua.txt for diffing against the Go
-- implementation's output.
--
-- Usage: lua lunar/cli/treedump.lua <root> [<root> ...]
--
-- Module roots are resolved relative to the workspace's `lunar/` folder
-- (which must be on package.path).

local Parser = require("compiler.parser")

---@param dir string
---@return string[]
local function findNarFiles(dir)
    local files = {}
    local pipe = io.popen('find "' .. dir .. '" -type f -name "*.nar"')
    if pipe == nil then
        error("failed to spawn find for " .. dir)
    end
    for line in pipe:lines() do
        files[#files + 1] = line
    end
    pipe:close()
    table.sort(files)
    return files
end

---@param path string
---@return string
local function readAll(path)
    local f, err = io.open(path, "rb")
    if f == nil then
        error("open " .. path .. ": " .. tostring(err))
    end
    local data = f:read("*a")
    f:close()
    return data
end

---@param path string
---@param data string
local function writeAll(path, data)
    local f, err = io.open(path, "wb")
    if f == nil then
        error("write " .. path .. ": " .. tostring(err))
    end
    f:write(data)
    f:close()
end

if #arg < 1 then
    io.stderr:write("usage: treedump <root> [<root> ...]\n")
    os.exit(2)
end

local totalOk, totalErr = 0, 0

for _, root in ipairs(arg) do
    for _, path in ipairs(findNarFiles(root)) do
        local content = readAll(path)
        local module, errors = Parser.parse(path, content)
        if module == nil or (errors ~= nil and #errors > 0) then
            totalErr = totalErr + 1
            local firstErr = (errors and errors[1]) or "unknown error"
            io.stderr:write("parse " .. path .. ": " .. tostring(firstErr) .. "\n")
        else
            writeAll(path .. ".tree.lua.txt", module:stringTree(0))
            totalOk = totalOk + 1
        end
    end
end

io.write(string.format("treedump: %d ok, %d failed\n", totalOk, totalErr))
