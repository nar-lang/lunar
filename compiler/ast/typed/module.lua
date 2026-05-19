---@class TypedModule
---@field name QualifiedIdentifier
---@field location Location
---@field dependencies table<QualifiedIdentifier, Identifier[]>
---@field definitions TypedDefinition[]
local TypedModule = {}
TypedModule.__index = TypedModule

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

return { TypedModule = TypedModule }
