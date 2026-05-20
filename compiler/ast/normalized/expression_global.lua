local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")
local utils = require("compiler.ast.normalized.utils")
local TyGlobal = require("compiler.ast.typed.expression_global").TyGlobal

---@class NGlobal : NormExpression
---@field kind "NGlobal"
---@field location Location
---@field moduleName QualifiedIdentifier
---@field definitionName Identifier
local NGlobal = setmetatable({}, { __index = NormExpression })
NGlobal.__index = NGlobal
 
---@param location Location
---@param moduleName QualifiedIdentifier
---@param definitionName Identifier
---@return NGlobal
function NGlobal.new(location, moduleName, definitionName)
    return setmetatable({
        kind = "NGlobal",
        location = location,
        moduleName = moduleName,
        definitionName = definitionName,
    }, NGlobal)
end

---@param f fun(stmt: NormStatement)
function NGlobal:iterate(f)
    f(self)
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NGlobal:flattenLambdas(parentName, m, locals)
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NGlobal:replaceLocals(replace)
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NGlobal:extractUsedLocalsSet(definedLocals, usedLocals)
end

---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param stack TypedDefinition[]
---@return TypedExpression|nil e
---@return string|nil err
function NGlobal:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    local targetDef, err = utils.getAnnotatedGlobal(
        self.moduleName, self.definitionName, modules, typedModules, stack, self.location)
    if err ~= nil then
        return nil, err
    end
    ---@cast targetDef -nil
    return self:setSuccessor(TyGlobal.new(
        ctx, self.location, self.moduleName, self.definitionName, targetDef))
end

return { NGlobal = NGlobal }
