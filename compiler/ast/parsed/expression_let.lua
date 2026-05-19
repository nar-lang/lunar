local Expression = require("compiler.ast.parsed.expression").Expression
local NLet = require("compiler.ast.normalized.expression_let").NLet
local cloneMap = require("compiler.ast.parsed.utils").cloneMap

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

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Let:normalize(locals, modules, module, normalizedModule)
    local innerLocals = cloneMap(locals)
    local pattern, err1 = self.pattern:normalize(innerLocals, modules, module, normalizedModule)
    if pattern == nil then
        return nil, err1
    end
    local value, err2 = self.value:normalize(innerLocals, modules, module, normalizedModule)
    if value == nil then
        return nil, err2
    end
    local nested, err3 = self.nested:normalize(innerLocals, modules, module, normalizedModule)
    if nested == nil then
        return nil, err3
    end
    return self:setSuccessor(NLet.new(self.location, pattern, value, nested)), nil
end

return { Let = Let }
