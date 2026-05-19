local Type = require("compiler.ast.parsed.type").Type
local NTTuple = require("compiler.ast.normalized.type_tuple").NTTuple

---@class TTuple : Type
---@field kind "TTuple"
---@field location Location
---@field items Type[]
local TTuple = setmetatable({}, { __index = Type })
TTuple.__index = TTuple

---@param location Location
---@param items Type[]
---@return TTuple
function TTuple.new(location, items)
    return setmetatable({
        kind = "TTuple",
        location = location,
        items = items or {},
    }, TTuple)
end

---@param f fun(stmt: Statement)
function TTuple:iterate(f)
    f(self)
    for _, item in ipairs(self.items) do
        item:iterate(f)
    end
end

---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param namedTypes NamedTypeMap|nil
---@return NormType|nil
---@return string|nil error
function TTuple:normalize(modules, module, namedTypes)
    local items = {}
    for i, item in ipairs(self.items) do
        local ni, err = item:normalize(modules, module, namedTypes)
        if err ~= nil then
            return nil, err
        end
        items[i] = ni
    end
    return self:setSuccessor(NTTuple.new(self.location, items)), nil
end

---@param params table<Identifier, Type>
---@param loc Location
---@return Type|nil
---@return string|nil error
function TTuple:applyArgs(params, loc)
    local items = {}
    for i, item in ipairs(self.items) do
        local ni, err = item:applyArgs(params, loc)
        if err ~= nil then
            return nil, err
        end
        items[i] = ni
    end
    return TTuple.new(loc, items), nil
end

return { TTuple = TTuple }
