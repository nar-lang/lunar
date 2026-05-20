local Expression = require("lunar.compiler.ast.parsed.expression").Expression
local NTuple = require("lunar.compiler.ast.normalized.expression_tuple").NTuple

---@class Tuple : Expression
---@field kind "Tuple"
---@field location Location
---@field items Expression[]
local Tuple = setmetatable({}, { __index = Expression })
Tuple.__index = Tuple

---@param location Location
---@param items Expression[]
---@return Tuple
function Tuple.new(location, items)
    return setmetatable({
        kind = "Tuple",
        location = location,
        items = items or {},
    }, Tuple)
end

---@param f fun(stmt: Statement)
function Tuple:iterate(f)
    f(self)
    for _, item in ipairs(self.items) do
        item:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Tuple:normalize(locals, modules, module, normalizedModule)
    local items = {}
    for i, item in ipairs(self.items) do
        local nItem, err = item:normalize(locals, modules, module, normalizedModule)
        if nItem == nil then
            return nil, err
        end
        items[i] = nItem
    end
    return self:setSuccessor(NTuple.new(self.location, items)), nil
end

return { Tuple = Tuple }
