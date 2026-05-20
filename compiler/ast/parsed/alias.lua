local Statement = require("compiler.ast.parsed.defines").Statement
local makeFullIdentifier = require("compiler.ast.misc").makeFullIdentifier

---@class Alias : Statement
---@field kind "Alias"
---@field location Location
---@field hidden boolean
---@field name Identifier
---@field params Identifier[]
---@field type Type?
---@field nameLocation Location
local Alias = setmetatable({}, { __index = Statement })
Alias.__index = Alias

---@param location Location
---@param hidden boolean
---@param name Identifier
---@param params Identifier[]
---@param type_ Type?
---@param nameLocation Location
---@return Alias
function Alias.new(location, hidden, name, params, type_, nameLocation)
    return setmetatable({
        kind = "Alias",
        location = location,
        hidden = hidden == true,
        name = name,
        params = params or {},
        type = type_,
        nameLocation = nameLocation,
    }, Alias)
end

---@return Type?
function Alias:aliasType()
    return self.type
end

---Infer the aliased type when referenced with `args` from `moduleName`.
---@param moduleName QualifiedIdentifier
---@param args Type[]
---@return Type?
---@return FullIdentifier
---@return string|nil error
function Alias:inferType(moduleName, args)
    local id = makeFullIdentifier(moduleName, self.name)
    if self.type == nil then
        local TNative = require("compiler.ast.parsed.type_native").TNative
        return TNative.new(self.location, id, args, self.nameLocation), id, nil
    end
    if #self.params ~= #args then
        return nil, "", string.format(
            "wrong number of type parameters, expected %d, got %d",
            #self.params, #args)
    end
    local typeMap = {}
    for i, p in ipairs(self.params) do
        typeMap[p] = args[i]
    end
    local applied, err = self.type:applyArgs(typeMap, self.location)
    if err ~= nil then
        return nil, "", err
    end
    ---@cast applied -nil
    return applied, id, nil
end

---@param f fun(stmt: Statement)
function Alias:iterate(f)
    f(self)
    if self.type ~= nil then
        self.type:iterate(f)
    end
end

return { Alias = Alias }
