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

local Expression = require("lunar.compiler.ast.parsed.expression").Expression
local NSelect = require("lunar.compiler.ast.normalized.expression_select").NSelect
local NSelectCase = require("lunar.compiler.ast.normalized.expression_select").NSelectCase
local cloneMap = require("lunar.compiler.ast.parsed.utils").cloneMap

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

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Select:normalize(locals, modules, module, normalizedModule)
    local condition, err = self.condition:normalize(locals, modules, module, normalizedModule)
    if condition == nil then
        return nil, err
    end
    local cases = {}
    for i, c in ipairs(self.cases) do
        local innerLocals = cloneMap(locals)
        local pattern, perr = c.pattern:normalize(innerLocals, modules, module, normalizedModule)
        if pattern == nil then
            return nil, perr
        end
        local body, berr = c.body:normalize(innerLocals, modules, module, normalizedModule)
        if body == nil then
            return nil, berr
        end
        cases[i] = NSelectCase.new(c.location, pattern, body)
    end
    return self:setSuccessor(NSelect.new(self.location, condition, cases)), nil
end

return { Select = Select, SelectCase = SelectCase }
