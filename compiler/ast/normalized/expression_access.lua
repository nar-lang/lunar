local NormExpression = require("lunar.compiler.ast.normalized.expression").NormExpression
local TyAccess = require("lunar.compiler.ast.typed.expression_access").TyAccess

---@class NAccess : NormExpression
---@field kind "NAccess"
---@field location Location
---@field record NormExpression
---@field fieldName Identifier
local NAccess = setmetatable({}, { __index = NormExpression })
NAccess.__index = NAccess

---@param location Location
---@param record NormExpression
---@param fieldName Identifier
---@return NAccess
function NAccess.new(location, record, fieldName)
    return setmetatable({
        kind = "NAccess",
        location = location,
        record = record,
        fieldName = fieldName,
    }, NAccess)
end

---@param f fun(stmt: NormStatement)
function NAccess:iterate(f)
    f(self)
    if self.record ~= nil then
        self.record:iterate(f)
    end
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NAccess:flattenLambdas(parentName, m, locals)
    self.record = self.record:flattenLambdas(parentName, m, locals)
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NAccess:replaceLocals(replace)
    self.record = self.record:replaceLocals(replace)
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NAccess:extractUsedLocalsSet(definedLocals, usedLocals)
    self.record:extractUsedLocalsSet(definedLocals, usedLocals)
end

---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param stack TypedDefinition[]
---@return TypedExpression|nil e
---@return string|nil err
function NAccess:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    local record, err = self.record:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    if err ~= nil then
        return nil, err
    end
    ---@cast record -nil
    return self:setSuccessor(TyAccess.new(ctx, self.location, self.fieldName, record))
end

return { NAccess = NAccess }
