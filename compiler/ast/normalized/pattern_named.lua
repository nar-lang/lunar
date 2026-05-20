local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPNamed : NormPattern
---@field kind "NPNamed"
---@field location Location
---@field declaredType NormType|nil
---@field name Identifier
local NPNamed = setmetatable({}, { __index = NormPattern })
NPNamed.__index = NPNamed

---@param location Location
---@param declaredType NormType|nil
---@param name Identifier
---@return NPNamed
function NPNamed.new(location, declaredType, name)
    return setmetatable({
        kind = "NPNamed",
        location = location,
        declaredType = declaredType,
        name = name,
    }, NPNamed)
end

---@param f fun(stmt: NormStatement)
function NPNamed:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals NormPatternMap
function NPNamed:extractLocals(locals)
    locals[self.name] = self
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
function NPNamed:annotate(ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    local utils = require("compiler.ast.normalized.utils")
    local TyPNamed = require("compiler.ast.typed.pattern_named").TyPNamed
    local declared, derr = utils.annotateTypeSafe(ctx, self.declaredType, typeParams, typeMapSource)
    if derr ~= nil then
        return nil, derr
    end
    ---@cast declared -nil
    return self:setSuccessor(TyPNamed.new(ctx, self.location, declared, self.name))
end

return { NPNamed = NPNamed }
