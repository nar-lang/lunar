local NormExpression = require("lunar.compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("lunar.compiler.ast.normalized.module")
local TyLet = require("lunar.compiler.ast.typed.expression_let").TyLet

---@class NLet : NormExpression
---@field kind "NLet"
---@field location Location
---@field pattern NormPattern
---@field value NormExpression
---@field nested NormExpression
local NLet = setmetatable({}, { __index = NormExpression })
NLet.__index = NLet

---@param location Location
---@param pattern NormPattern
---@param value NormExpression
---@param nested NormExpression
---@return NLet
function NLet.new(location, pattern, value, nested)
    return setmetatable({
        kind = "NLet",
        location = location,
        pattern = pattern,
        value = value,
        nested = nested,
    }, NLet)
end

---@param f fun(stmt: NormStatement)
function NLet:iterate(f)
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
function NLet:flattenLambdas(parentName, m, locals)
    local innerLocals = cloneLocals(locals)
    self.pattern:extractLocals(innerLocals)
    self.value = self.value:flattenLambdas(parentName, m, innerLocals)
    self.nested = self.nested:flattenLambdas(parentName, m, innerLocals)
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NLet:replaceLocals(replace)
    self.value = self.value:replaceLocals(replace)
    self.nested = self.nested:replaceLocals(replace)
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NLet:extractUsedLocalsSet(definedLocals, usedLocals)
    self.value:extractUsedLocalsSet(definedLocals, usedLocals)
    self.nested:extractUsedLocalsSet(definedLocals, usedLocals)
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
function NLet:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    local localTypeParams = cloneTypeParams(typeParams)
    local pattern, err = self.pattern:annotate(
        ctx, localTypeParams, modules, typedModules, moduleName, true, stack)
    if err ~= nil then
        return nil, err
    end
    ---@cast pattern -nil
    local value, verr = self.value:annotate(
        ctx, localTypeParams, modules, typedModules, moduleName, stack)
    if verr ~= nil then
        return nil, verr
    end
    ---@cast value -nil
    local body, berr = self.nested:annotate(
        ctx, localTypeParams, modules, typedModules, moduleName, stack)
    if berr ~= nil then
        return nil, berr
    end
    ---@cast body -nil
    return self:setSuccessor(TyLet.new(ctx, self.location, pattern, value, body))
end

return { NLet = NLet }
