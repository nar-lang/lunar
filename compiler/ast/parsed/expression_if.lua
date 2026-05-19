local Expression = require("compiler.ast.parsed.expression").Expression

---@class If : Expression
---@field kind "If"
---@field location Location
---@field condition Expression
---@field positive Expression
---@field negative Expression
local If = setmetatable({}, { __index = Expression })
If.__index = If

---@param location Location
---@param condition Expression
---@param positive Expression
---@param negative Expression
---@return If
function If.new(location, condition, positive, negative)
    return setmetatable({
        kind = "If",
        location = location,
        condition = condition,
        positive = positive,
        negative = negative,
    }, If)
end

---@param f fun(stmt: Statement)
function If:iterate(f)
    f(self)
    if self.condition ~= nil then
        self.condition:iterate(f)
    end
    if self.positive ~= nil then
        self.positive:iterate(f)
    end
    if self.negative ~= nil then
        self.negative:iterate(f)
    end
end

---@return nil
---@return string
function If:normalize()
    return nil, "TODO: normalize"
end

return { If = If }
