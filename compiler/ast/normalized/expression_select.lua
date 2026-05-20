local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")
local selectMod = require("compiler.ast.typed.expression_select")

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

---@param src TypeParamsMap
---@return TypeParamsMap
local function cloneTypeParams(src)
    local out = {}
    for k, v in pairs(src) do
        out[k] = v
    end
    return out
end

---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param stack TypedDefinition[]
---@return TypedExpression|nil e
---@return string|nil err
function NSelect:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    local TySelect = selectMod.TySelect
    local TySelectCase = selectMod.TySelectCase
    local condition, err = self.condition:annotate(
        ctx, typeParams, modules, typedModules, moduleName, stack)
    if err ~= nil then
        return nil, err
    end
    ---@cast condition -nil
    ---@type table[]
    local cases = {}
    for i, c in ipairs(self.cases) do
        local localTypeParams = cloneTypeParams(typeParams)
        local pattern, perr = c.pattern:annotate(
            ctx, localTypeParams, modules, typedModules, moduleName, false, stack)
        if perr ~= nil then
            return nil, perr
        end
        ---@cast pattern -nil
        local expr, eerr = c.expression:annotate(
            ctx, localTypeParams, modules, typedModules, moduleName, stack)
        if eerr ~= nil then
            return nil, eerr
        end
        ---@cast expr -nil
        cases[i] = TySelectCase.new(c.location, pattern, expr)
    end
    return self:setSuccessor(TySelect.new(ctx, self.location, condition, cases))
end

return { NSelect = NSelect, NSelectCase = NSelectCase }
