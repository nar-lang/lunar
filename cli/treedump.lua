-- Tree dump CLI: walks one or more directories, parses every *.nar file
-- with compiler.parser and writes the parsed AST tree (via
-- module:stringTree(0)) to <file>.tree.lua.txt for diffing against the Go
-- implementation's output.
--
-- With the `--normalized` flag, all `.nar` files under the given roots are
-- parsed first, generate + normalize is run with the full module map, and the
-- normalized AST tree is written to `<file>.tree.normalized.lua.txt`.
--
-- Usage: lua lunar/cli/treedump.lua [--normalized] <root> [<root> ...]
--
-- Module roots are resolved relative to the workspace's `lunar/` folder
-- (which must be on package.path).

local Parser = require("compiler.parser")
local NormalizedTreePrint = require("compiler.ast.normalized.tree_print")

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

local normalizedMode = false
local roots = {}
for _, a in ipairs(arg) do
    if a == "--normalized" then
        normalizedMode = true
    else
        roots[#roots + 1] = a
    end
end

if #roots < 1 then
    io.stderr:write("usage: treedump [--normalized] <root> [<root> ...]\n")
    os.exit(2)
end

if not normalizedMode then
    local totalOk, totalErr = 0, 0
    for _, root in ipairs(roots) do
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
    return
end

-- normalized mode -----------------------------------------------------------

local totalErr = 0

-- 1) Gather all .nar files
---@type string[]
local allFiles = {}
for _, root in ipairs(roots) do
    for _, path in ipairs(findNarFiles(root)) do
        allFiles[#allFiles + 1] = path
    end
end
table.sort(allFiles)

-- 2) Parse all
---@type table<QualifiedIdentifier, Module>
local parsedModules = {}
---@type table<QualifiedIdentifier, string>
local moduleFile = {}
for _, path in ipairs(allFiles) do
    local content = readAll(path)
    local m, errors = Parser.parse(path, content)
    if m == nil or (errors ~= nil and #errors > 0) then
        totalErr = totalErr + 1
        local firstErr = (errors and errors[1]) or "unknown error"
        io.stderr:write("parse " .. path .. ": " .. tostring(firstErr) .. "\n")
    else
        ---@cast m Module
        parsedModules[m.name] = m
        moduleFile[m.name] = path
    end
end

-- 3) Generate (lower data types, expand imports)
---@type QualifiedIdentifier[]
local names = {}
for n in pairs(parsedModules) do
    names[#names + 1] = n
end
table.sort(names)

for _, n in ipairs(names) do
    local errs = parsedModules[n]:generate(parsedModules)
    if errs ~= nil then
        for _, e in ipairs(errs) do
            io.stderr:write("generate " .. tostring(n) .. ": " .. tostring(e) .. "\n")
            totalErr = totalErr + 1
        end
    end
end

-- 4) Normalize
---@type table<QualifiedIdentifier, NormModule>
local normalizedModules = {}
for _, n in ipairs(names) do
    local errs = parsedModules[n]:normalize(parsedModules, normalizedModules)
    if errs ~= nil then
        for _, e in ipairs(errs) do
            io.stderr:write("normalize " .. tostring(n) .. ": " .. tostring(e) .. "\n")
            totalErr = totalErr + 1
        end
    end
end

-- 5) Write outputs
local totalOk = 0
for _, n in ipairs(names) do
    local nm = normalizedModules[n]
    local path = moduleFile[n]
    if nm ~= nil and path ~= nil then
        writeAll(path .. ".tree.normalized.lua.txt", NormalizedTreePrint.moduleStringTree(nm, 0))
        totalOk = totalOk + 1
    end
end

io.write(string.format("treedump (normalized): %d ok, %d failed\n", totalOk, totalErr))
