local Expression = require("compiler.ast.parsed.expression").Expression

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

---@return nil
---@return string
function List:normalize()
    return nil, "TODO: normalize"
end

return { List = List }
