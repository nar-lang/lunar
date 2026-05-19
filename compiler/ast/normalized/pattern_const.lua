local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPConst : NormPattern
---@field kind "NPConst"
---@field location Location
---@field declaredType NormType|nil
---@field value ConstValue
local NPConst = setmetatable({}, { __index = NormPattern })
NPConst.__index = NPConst

---@param location Location
---@param declaredType NormType|nil
---@param value ConstValue
---@return NPConst
function NPConst.new(location, declaredType, value)
    return setmetatable({
        kind = "NPConst",
        location = location,
        declaredType = declaredType,
        value = value,
    }, NPConst)
end

---@param f fun(stmt: NormStatement)
function NPConst:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals NormPatternMap
function NPConst:extractLocals(locals)
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
function NPConst:annotate(ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    local utils = require("compiler.ast.normalized.utils")
    local TyPConst = require("compiler.ast.typed.pattern_const").TyPConst
    local declared, derr = utils.annotateTypeSafe(ctx, self.declaredType, typeParams, typeMapSource)
    if derr ~= nil then
        return nil, derr
    end
    return self:setSuccessor(TyPConst.new(ctx, self.location, declared, self.value))
end

return { NPConst = NPConst }
