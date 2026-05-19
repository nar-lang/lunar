---@class TypedModule
---@field name QualifiedIdentifier
---@field location Location
---@field dependencies table<QualifiedIdentifier, Identifier[]>
---@field definitions TypedDefinition[]
local TypedModule = {}
TypedModule.__index = TypedModule

local builtins = require("compiler.common.builtins")
local binaryMod = require("compiler.bytecode.binary")

---@param location Location
---@param name QualifiedIdentifier
---@param dependencies table<QualifiedIdentifier, Identifier[]>
---@param definitions TypedDefinition[]
---@return TypedModule
function TypedModule.new(location, name, dependencies, definitions)
    return setmetatable({
        name = name,
        location = location,
        dependencies = dependencies or {},
        definitions = definitions or {},
    }, TypedModule)
end

---@param def TypedDefinition
function TypedModule:addDefinition(def)
    self.definitions[#self.definitions + 1] = def
end

---@param name Identifier
---@return TypedDefinition|nil, boolean
function TypedModule:findDefinition(name)
    for _, def in ipairs(self.definitions) do
        if def.name == name then
            return def, true
        end
    end
    return nil, false
end

---@return string[]
function TypedModule:checkTypes()
    ---@type string[]
    local errors = {}
    for _, def in ipairs(self.definitions) do
        if not def.typed then
            local err = def:solveTypes(nil)
            if err ~= nil then
                errors[#errors + 1] = err
            end
        end
    end
    return errors
end

---@return string[]
function TypedModule:checkPatterns()
    ---@type string[]
    local errors = {}
    for _, def in ipairs(self.definitions) do
        local err = def:checkPatterns()
        if err ~= nil then
            errors[#errors + 1] = err
        end
    end
    return errors
end

---@param modules table<QualifiedIdentifier, TypedModule>
---@param debug boolean
---@param binary Binary
---@param hash BinaryHash
---@return string|nil err
function TypedModule:compose(modules, debug, binary, hash)
    hash:hashString("", binary)

    for _, p in ipairs(hash.compiledPaths) do
        if p == self.name then
            return nil
        end
    end
    hash.compiledPaths[#hash.compiledPaths + 1] = self.name

    -- Sort dependency names for deterministic order (Go iterates `range` on a
    -- map which is non-deterministic, but the dependent modules eventually
    -- end up in the same order because each compiles its own deps first).
    -- Sorting here also ensures byte-identical output across runs.
    local depNames = {}
    for depName in pairs(self.dependencies) do
        depNames[#depNames + 1] = depName
    end
    table.sort(depNames)
    for _, depName in ipairs(depNames) do
        local m = modules[depName]
        if m == nil then
            return string.format("module '%s' not found", depName)
        end
        local err = m:compose(modules, debug, binary, hash)
        if err ~= nil then
            return err
        end
    end

    -- Reserve placeholder Func entries so recursive references can resolve.
    for _, def in ipairs(self.definitions) do
        local extId = builtins.makeFullIdentifier(self.name, def.name)
        hash.funcsMap[extId] = #binary.funcs
        binary.funcs[#binary.funcs + 1] = binaryMod.Func.new(0, 0, {}, "", {})
    end

    for _, def in ipairs(self.definitions) do
        local pathId = builtins.makeFullIdentifier(self.name, def.name)
        local ptr = hash.funcsMap[pathId]
        -- Lua's #funcs[ptr+1].ops is 0 for the placeholder; we use that as
        -- the "already filled" check (Go uses `ops == nil`).
        local existing = binary.funcs[ptr + 1]
        if #existing.ops == 0 and existing.numArgs == 0 and existing.name == 0 then
            binary.funcs[ptr + 1] = def:bytecode(pathId, self.name, binary, hash)
            if not def.hidden then
                binary.exports[pathId] = ptr
            end
        end
    end
    return nil
end

return { TypedModule = TypedModule }
