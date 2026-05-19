local Expression = require("compiler.ast.parsed.expression").Expression

---@class Negate : Expression
---@field kind "Negate"
---@field location Location
---@field nested Expression
local Negate = setmetatable({}, { __index = Expression })
Negate.__index = Negate

---@param location Location
---@param nested Expression
---@return Negate
function Negate.new(location, nested)
    return setmetatable({
        kind = "Negate",
        location = location,
        nested = nested,
    }, Negate)
end

---@param f fun(stmt: Statement)
function Negate:iterate(f)
    f(self)
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
end

---@return nil
---@return string
function Negate:normalize()
    return nil, "TODO: normalize"
end

return { Negate = Negate }
