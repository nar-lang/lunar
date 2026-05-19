local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")

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

return { NGlobal = NGlobal }
