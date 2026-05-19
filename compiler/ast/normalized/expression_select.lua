local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")

---@class NSelectCase
---@field location Location
---@field pattern NormPattern
---@field expression NormExpression
local NSelectCase = {}
NSelectCase.__index = NSelectCase

---@param location Location
---@param pattern NormPattern
---@param expression NormExpression
---@return NSelectCase
function NSelectCase.new(location, pattern, expression)
    return setmetatable({
        location = location,
        pattern = pattern,
        expression = expression,
    }, NSelectCase)
end

---@class NSelect : NormExpression
---@field kind "NSelect"
---@field location Location
---@field condition NormExpression
---@field cases NSelectCase[]
local NSelect = setmetatable({}, { __index = NormExpression })
NSelect.__index = NSelect

---@param location Location
---@param condition NormExpression
---@param cases NSelectCase[]
---@return NSelect
function NSelect.new(location, condition, cases)
    return setmetatable({
        kind = "NSelect",
        location = location,
        condition = condition,
        cases = cases or {},
    }, NSelect)
end

---@param f fun(stmt: NormStatement)
function NSelect:iterate(f)
    f(self)
    if self.condition ~= nil then
        self.condition:iterate(f)
    end
    for _, c in ipairs(self.cases) do
        if c ~= nil then
            if c.pattern ~= nil then
                c.pattern:iterate(f)
            end
            if c.expression ~= nil then
                c.expression:iterate(f)
            end
        end
    end
end

---@param src NormPatternMap
---@return NormPatternMap
local function cloneLocals(src)
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NSelect:flattenLambdas(parentName, m, locals)
    self.condition = self.condition:flattenLambdas(parentName, m, locals)
    for _, c in ipairs(self.cases) do
        local innerLocals = cloneLocals(locals)
        c.pattern:extractLocals(innerLocals)
        c.expression = c.expression:flattenLambdas(parentName, m, innerLocals)
    end
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NSelect:replaceLocals(replace)
    self.condition = self.condition:replaceLocals(replace)
    for _, c in ipairs(self.cases) do
        c.expression = c.expression:replaceLocals(replace)
    end
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NSelect:extractUsedLocalsSet(definedLocals, usedLocals)
    self.condition:extractUsedLocalsSet(definedLocals, usedLocals)
    for _, c in ipairs(self.cases) do
        c.expression:extractUsedLocalsSet(definedLocals, usedLocals)
    end
end

return { NSelect = NSelect, NSelectCase = NSelectCase }
