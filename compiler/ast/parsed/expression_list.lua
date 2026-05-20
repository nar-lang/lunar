local Expression = require("lunar.compiler.ast.parsed.expression").Expression
local NList = require("lunar.compiler.ast.normalized.expression_list").NList

---@class List : Expression
---@field kind "List"
---@field location Location
---@field items Expression[]
local List = setmetatable({}, { __index = Expression })
List.__index = List

---@param location Location
---@param items Expression[]
---@return List
function List.new(location, items)
    return setmetatable({
        kind = "List",
        location = location,
        items = items or {},
    }, List)
end

---@param f fun(stmt: Statement)
function List:iterate(f)
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
function List:normalize(locals, modules, module, normalizedModule)
    local items = {}
    for i, item in ipairs(self.items) do
        local nItem, err = item:normalize(locals, modules, module, normalizedModule)
        if nItem == nil then
            return nil, err
        end
        items[i] = nItem
    end
    return self:setSuccessor(NList.new(self.location, items)), nil
end

return { List = List }
