local Expression = require("compiler.ast.parsed.expression").Expression

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

---@return nil
---@return string
function Tuple:normalize()
    return nil, "TODO: normalize"
end

return { Tuple = Tuple }
