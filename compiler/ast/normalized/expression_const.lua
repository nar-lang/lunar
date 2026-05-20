local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")
local TyConst = require("compiler.ast.typed.expression_const").TyConst

---@class NConst : NormExpression
---@field kind "NConst"
---@field location Location
---@field value ConstValue
local NConst = setmetatable({}, { __index = NormExpression })
NConst.__index = NConst

---@param location Location
---@param value ConstValue
---@return NConst
function NConst.new(location, value)
    return setmetatable({
        kind = "NConst",
        location = location,
        value = value,
    }, NConst)
end

---@param f fun(stmt: NormStatement)
function NConst:iterate(f)
    f(self)
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NConst:flattenLambdas(parentName, m, locals)
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NConst:replaceLocals(replace)
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NConst:extractUsedLocalsSet(definedLocals, usedLocals)
end

---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param stack TypedDefinition[]
---@return TypedExpression|nil e
---@return string|nil err
function NConst:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    return self:setSuccessor(TyConst.new(ctx, self.location, self.value))
end

return { NConst = NConst }
