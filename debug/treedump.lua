-- Tree dump CLI: walks one or more directories, parses every *.nar file
-- with compiler.parser and writes the parsed AST tree (via
-- ParsedTreePrint.stringTree(module, 0)) to <file>.tree.lua.txt for diffing
-- against the Go implementation's output.
--
-- With the `--normalized` flag, all `.nar` files under the given roots are
-- parsed first, generate + normalize is run with the full module map, and the
-- normalized AST tree is written to `<file>.tree.normalized.lua.txt`.
--
-- With the `--typed` flag, normalized modules are additionally lowered into
-- the typed AST via `module:annotate(...)` and the resulting typed tree is
-- written to `<file>.tree.typed.lua.txt`.
--
-- With the `--checked` flag, typed modules additionally run checkTypes()
-- (Hindley-Milner unification) and checkPatterns() (exhaustiveness +
-- redundancy). The resulting fully-typed tree is written to
-- `<file>.tree.checked.lua.txt`.
--
-- Usage: lua lunar/debug/treedump.lua [--normalized | --typed | --checked | --bytecode] <root> [<root> ...]
--
-- Module roots are resolved relative to the workspace's `lunar/` folder
-- (which must be on package.path).

local Parser = require("lunar.compiler.parser")
local ParsedTreePrint = require("lunar.debug.tree_print.parsed")
local NormalizedTreePrint = require("lunar.debug.tree_print.normalized")
local TypedTreePrint = require("lunar.debug.tree_print.typed")
local BinaryMod = require("lunar.compiler.bytecode.binary")
local BinaryHashMod = require("lunar.compiler.bytecode.binary_hash")

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
local typedMode = false
local checkedMode = false
local bytecodeMode = false
local roots = {}
for _, a in ipairs(arg) do
    if a == "--normalized" then
        normalizedMode = true
    elseif a == "--typed" then
        typedMode = true
        normalizedMode = true
    elseif a == "--checked" then
        checkedMode = true
        typedMode = true
        normalizedMode = true
    elseif a == "--bytecode" then
        bytecodeMode = true
        checkedMode = true
        typedMode = true
        normalizedMode = true
    else
        roots[#roots + 1] = a
    end
end

if #roots < 1 then
    io.stderr:write("usage: treedump [--normalized | --typed | --checked | --bytecode] <root> [<root> ...]\n")
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
                writeAll(path .. ".tree.lua.txt", ParsedTreePrint.stringTree(module, 0))
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

if not typedMode then
    return
end

-- typed mode --------------------------------------------------------------

-- 6) Annotate each normalized module into a typed module.
---@type table<QualifiedIdentifier, TypedModule>
local typedModules = {}
for _, n in ipairs(names) do
    local nm = normalizedModules[n]
    if nm ~= nil then
        local errs = nm:annotate(normalizedModules, typedModules)
        if errs ~= nil then
            for _, e in ipairs(errs) do
                io.stderr:write("annotate " .. tostring(n) .. ": " .. tostring(e) .. "\n")
                totalErr = totalErr + 1
            end
        end
    end
end

-- 7) Write typed outputs.
local typedOk = 0
for _, n in ipairs(names) do
    local tm = typedModules[n]
    local path = moduleFile[n]
    if tm ~= nil and path ~= nil then
        writeAll(path .. ".tree.typed.lua.txt", TypedTreePrint.moduleStringTree(tm, 0))
        typedOk = typedOk + 1
    end
end

io.write(string.format("treedump (typed): %d ok, %d failed\n", typedOk, totalErr))

if not checkedMode then
    return
end

-- checked mode ------------------------------------------------------------

-- 8) Run Hindley-Milner type checking on every typed module.
for _, n in ipairs(names) do
    local tm = typedModules[n]
    if tm ~= nil then
        local errs = tm:checkTypes()
        if errs ~= nil then
            for _, e in ipairs(errs) do
                io.stderr:write("checkTypes " .. tostring(n) .. ": " .. tostring(e) .. "\n")
                totalErr = totalErr + 1
            end
        end
    end
end

-- 9) Run pattern-match exhaustiveness/redundancy checks.
for _, n in ipairs(names) do
    local tm = typedModules[n]
    if tm ~= nil then
        local errs = tm:checkPatterns()
        if errs ~= nil then
            for _, e in ipairs(errs) do
                io.stderr:write("checkPatterns " .. tostring(n) .. ": " .. tostring(e) .. "\n")
                totalErr = totalErr + 1
            end
        end
    end
end

-- 10) Write checked outputs (fully-typed tree dump).
local checkedOk = 0
for _, n in ipairs(names) do
    local tm = typedModules[n]
    local path = moduleFile[n]
    if tm ~= nil and path ~= nil then
        writeAll(path .. ".tree.checked.lua.txt", TypedTreePrint.moduleStringTree(tm, 0))
        checkedOk = checkedOk + 1
    end
end

io.write(string.format("treedump (checked): %d ok, %d failed\n", checkedOk, totalErr))

if not bytecodeMode then
    return
end

-- bytecode mode -----------------------------------------------------------

-- 11) For each root, build a single Binary blob from all typed modules under
-- that root. (Mirrors the Go reference: nar_compiler.Compile sorts module
-- names then calls Compose on each.)

---@param root string
---@return QualifiedIdentifier[] sorted module names under this root
local function modulesUnderRoot(root)
    local rootFiles = {}
    for _, p in ipairs(findNarFiles(root)) do
        rootFiles[p] = true
    end
    local result = {}
    for _, n in ipairs(names) do
        local path = moduleFile[n]
        if path ~= nil and rootFiles[path] then
            result[#result + 1] = n
        end
    end
    table.sort(result)
    return result
end

local bytecodeOk = 0
for _, root in ipairs(roots) do
    local rootNames = modulesUnderRoot(root)
    if #rootNames == 0 then
        goto continue_root
    end

    local binary = BinaryMod.Binary.new()
    local hash = BinaryHashMod.BinaryHash.new()

    local composeOk = true
    for _, n in ipairs(rootNames) do
        local tm = typedModules[n]
        if tm == nil then
            io.stderr:write("compose " .. tostring(n) .. ": typed module missing\n")
            totalErr = totalErr + 1
            composeOk = false
            break
        end
        local err = tm:compose(typedModules, true, binary, hash)
        if err ~= nil then
            io.stderr:write("compose " .. tostring(n) .. ": " .. tostring(err) .. "\n")
            totalErr = totalErr + 1
            composeOk = false
            break
        end
    end

    if composeOk then
        local outPath = root .. "/binary.lua.bin"
        local f, err = io.open(outPath, "wb")
        if f == nil then
            io.stderr:write("write " .. outPath .. ": " .. tostring(err) .. "\n")
            totalErr = totalErr + 1
        else
            f:write(binary:build(true))
            f:close()
            bytecodeOk = bytecodeOk + 1
        end
    end

    ::continue_root::
end

io.write(string.format("treedump (bytecode): %d ok, %d failed\n", bytecodeOk, totalErr))
