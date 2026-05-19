local Expression = require("compiler.ast.parsed.expression").Expression

---@class Let : Expression
---@field kind "Let"
---@field location Location
---@field pattern Pattern
---@field value Expression
---@field nested Expression
local Let = setmetatable({}, { __index = Expression })
Let.__index = Let

---@param location Location
---@param pattern Pattern
---@param value Expression
---@param nested Expression
---@return Let
function Let.new(location, pattern, value, nested)
    return setmetatable({
        kind = "Let",
        location = location,
        pattern = pattern,
        value = value,
        nested = nested,
    }, Let)
end

---@param f fun(stmt: Statement)
function Let:iterate(f)
    f(self)
    if self.pattern ~= nil then
        self.pattern:iterate(f)
    end
    if self.value ~= nil then
        self.value:iterate(f)
    end
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
end

---@return nil
---@return string
function Let:normalize()
    return nil, "TODO: normalize"
end

return { Let = Let }
