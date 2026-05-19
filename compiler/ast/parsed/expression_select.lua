---@class SelectCase
---@field location Location
---@field pattern Pattern
---@field body Expression
local SelectCase = {}
SelectCase.__index = SelectCase

---@param location Location
---@param pattern Pattern
---@param body Expression
---@return SelectCase
function SelectCase.new(location, pattern, body)
    return setmetatable({
        location = location,
        pattern = pattern,
        body = body,
    }, SelectCase)
end

local Expression = require("compiler.ast.parsed.expression").Expression

---@class Select : Expression
---@field kind "Select"
---@field location Location
---@field condition Expression
---@field cases SelectCase[]
local Select = setmetatable({}, { __index = Expression })
Select.__index = Select

---@param location Location
---@param condition Expression
---@param cases SelectCase[]
---@return Select
function Select.new(location, condition, cases)
    return setmetatable({
        kind = "Select",
        location = location,
        condition = condition,
        cases = cases or {},
    }, Select)
end

---@param f fun(stmt: Statement)
function Select:iterate(f)
    f(self)
    if self.condition ~= nil then
        self.condition:iterate(f)
    end
    for _, c in ipairs(self.cases) do
        if c.pattern ~= nil then
            c.pattern:iterate(f)
        end
        if c.body ~= nil then
            c.body:iterate(f)
        end
    end
end

---@return nil
---@return string
function Select:normalize()
    return nil, "TODO: normalize"
end

return { Select = Select, SelectCase = SelectCase }
