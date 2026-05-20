local NormStatement = require("lunar.compiler.ast.normalized.defines").NormStatement

---@class NormPattern : NormStatement
---@field kind string
---@field location Location
---@field declaredType NormType|nil
local NormPattern = setmetatable({}, { __index = NormStatement })
NormPattern.__index = NormPattern

---@param locals NormPatternMap
function NormPattern:extractLocals(locals)
    error("abstract method 'extractLocals' not implemented for kind=" .. tostring(self.kind), 2)
end

---Annotate a normalized pattern into a typed pattern.
---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param typeMapSource boolean
---@param stack TypedDefinition[]
---@return TypedPattern|nil p
---@return string|nil err
function NormPattern:annotate(ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    error("abstract method 'annotate' not implemented for kind=" .. tostring(self.kind), 2)
end

return { NormPattern = NormPattern }
