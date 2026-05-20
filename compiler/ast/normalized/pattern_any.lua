local NormPattern = require("lunar.compiler.ast.normalized.pattern").NormPattern
local utils = require("lunar.compiler.ast.normalized.utils")
local TyPAny = require("lunar.compiler.ast.typed.pattern_any").TyPAny

---@class NPAny : NormPattern
---@field kind "NPAny"
---@field location Location
---@field declaredType NormType|nil
local NPAny = setmetatable({}, { __index = NormPattern })
NPAny.__index = NPAny

---@param location Location
---@param declaredType NormType|nil
---@return NPAny
function NPAny.new(location, declaredType)
    return setmetatable({
        kind = "NPAny",
        location = location,
        declaredType = declaredType,
    }, NPAny)
end

---@param f fun(stmt: NormStatement)
function NPAny:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals NormPatternMap
function NPAny:extractLocals(locals)
end

---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param typeMapSource boolean
---@param stack TypedDefinition[]
---@return TypedPattern|nil p
---@return string|nil err
function NPAny:annotate(ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    local declared, derr = utils.annotateTypeSafe(ctx, self.declaredType, typeParams, typeMapSource)
    if derr ~= nil then
        return nil, derr
    end
    ---@cast declared -nil
    return self:setSuccessor(TyPAny.new(ctx, self.location, declared))
end

return { NPAny = NPAny }
