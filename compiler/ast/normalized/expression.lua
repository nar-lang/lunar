local NormStatement = require("compiler.ast.normalized.defines").NormStatement
-- Pull NormModule into scope so LuaLS can resolve ---@param m NormModule
-- annotations on subclasses. Suppressed at runtime via the underscore var.
local _NormModuleMod = require("compiler.ast.normalized.module")

---@class NormExpression : NormStatement
---@field kind string
---@field location Location
local NormExpression = setmetatable({}, { __index = NormStatement })
NormExpression.__index = NormExpression

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NormExpression:flattenLambdas(parentName, m, locals)
    error("abstract method 'flattenLambdas' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NormExpression:replaceLocals(replace)
    error("abstract method 'replaceLocals' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NormExpression:extractUsedLocalsSet(definedLocals, usedLocals)
    error("abstract method 'extractUsedLocalsSet' not implemented for kind=" .. tostring(self.kind), 2)
end

---Annotate a normalized expression into a typed expression.
---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param stack TypedDefinition[]
---@return TypedExpression|nil e
---@return string|nil err
function NormExpression:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    error("abstract method 'annotate' not implemented for kind=" .. tostring(self.kind), 2)
end

return { NormExpression = NormExpression }
