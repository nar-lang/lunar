local NormPattern = require("lunar.compiler.ast.normalized.pattern").NormPattern
local utils = require("lunar.compiler.ast.normalized.utils")
local TyPAlias = require("lunar.compiler.ast.typed.pattern_alias").TyPAlias

---@class NPAlias : NormPattern
---@field kind "NPAlias"
---@field location Location
---@field declaredType NormType|nil
---@field alias Identifier
---@field nested NormPattern
local NPAlias = setmetatable({}, { __index = NormPattern })
NPAlias.__index = NPAlias

---@param location Location
---@param declaredType NormType|nil
---@param alias Identifier
---@param nested NormPattern
---@return NPAlias
function NPAlias.new(location, declaredType, alias, nested)
    return setmetatable({
        kind = "NPAlias",
        location = location,
        declaredType = declaredType,
        alias = alias,
        nested = nested,
    }, NPAlias)
end

---@param f fun(stmt: NormStatement)
function NPAlias:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
end

---@param locals NormPatternMap
function NPAlias:extractLocals(locals)
    locals[self.alias] = self
    if self.nested ~= nil then
        self.nested:extractLocals(locals)
    end
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
function NPAlias:annotate(ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    local nested, err = self.nested:annotate(
        ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    if err ~= nil then
        return nil, err
    end
    ---@cast nested -nil
    local declared, derr = utils.annotateTypeSafe(ctx, self.declaredType, typeParams, typeMapSource)
    if derr ~= nil then
        return nil, derr
    end
    ---@cast declared -nil
    return self:setSuccessor(TyPAlias.new(ctx, self.location, declared, self.alias, nested))
end

return { NPAlias = NPAlias }
