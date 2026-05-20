local NormExpression = require("lunar.compiler.ast.normalized.expression").NormExpression
local utils = require("lunar.compiler.ast.normalized.utils")
local recordMod = require("lunar.compiler.ast.typed.expression_record")
local TyUpdate = require("lunar.compiler.ast.typed.expression_update").TyUpdate

---Record update expression. When `moduleName` is non-nil the update targets a
---module-level definition (Global). Otherwise it targets the local bound by
---`target` whose name is `recordName`.
---@class NUpdate : NormExpression
---@field kind "NUpdate"
---@field location Location
---@field moduleName QualifiedIdentifier|nil
---@field recordName Identifier
---@field fields NRecordField[]
---@field target NormPattern|nil
local NUpdate = setmetatable({}, { __index = NormExpression })
NUpdate.__index = NUpdate

---@param location Location
---@param recordName Identifier
---@param target NormPattern
---@param fields NRecordField[]
---@return NUpdate
function NUpdate.newLocal(location, recordName, target, fields)
    return setmetatable({
        kind = "NUpdate",
        location = location,
        moduleName = nil,
        recordName = recordName,
        target = target,
        fields = fields or {},
    }, NUpdate)
end

---@param location Location
---@param moduleName QualifiedIdentifier
---@param definitionName Identifier
---@param fields NRecordField[]
---@return NUpdate
function NUpdate.newGlobal(location, moduleName, definitionName, fields)
    return setmetatable({
        kind = "NUpdate",
        location = location,
        moduleName = moduleName,
        recordName = definitionName,
        target = nil,
        fields = fields or {},
    }, NUpdate)
end

---@param f fun(stmt: NormStatement)
function NUpdate:iterate(f)
    f(self)
    for _, fld in ipairs(self.fields) do
        if fld ~= nil and fld.value ~= nil then
            fld.value:iterate(f)
        end
    end
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NUpdate:flattenLambdas(parentName, m, locals)
    for _, fld in ipairs(self.fields) do
        fld.value = fld.value:flattenLambdas(parentName, m, locals)
    end
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NUpdate:replaceLocals(replace)
    for _, fld in ipairs(self.fields) do
        fld.value = fld.value:replaceLocals(replace)
    end
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NUpdate:extractUsedLocalsSet(definedLocals, usedLocals)
    for _, fld in ipairs(self.fields) do
        fld.value:extractUsedLocalsSet(definedLocals, usedLocals)
    end
end

---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param stack TypedDefinition[]
---@return TypedExpression|nil e
---@return string|nil err
function NUpdate:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    local TyRecordField = recordMod.TyRecordField
    ---@type table[]
    local fields = {}
    for i, f in ipairs(self.fields) do
        local value, err = f.value:annotate(
            ctx, typeParams, modules, typedModules, moduleName, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast value -nil
        fields[i] = TyRecordField.new(ctx, f.location, f.name, value)
    end
    if self.moduleName ~= nil and self.moduleName ~= "" then
        local targetDef, err = utils.getAnnotatedGlobal(
            self.moduleName, self.recordName, modules, typedModules, stack, self.location)
        if err ~= nil then
            return nil, err
        end
        ---@cast targetDef -nil
        return self:setSuccessor(TyUpdate.newGlobal(
            ctx, self.location, self.moduleName, self.recordName, targetDef, fields))
    end
    if self.target == nil then
        return nil, string.format("local variable `%s` not resolved", tostring(self.recordName))
    end
    local successor = self.target.successor
    ---@cast successor TypedPattern
    return self:setSuccessor(TyUpdate.newLocal(
        ctx, self.location, self.recordName, successor, fields))
end

return { NUpdate = NUpdate }
