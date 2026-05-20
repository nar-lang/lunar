local NormExpression = require("lunar.compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("lunar.compiler.ast.normalized.module")
local recordMod = require("lunar.compiler.ast.typed.expression_record")

---@class NRecordField
---@field location Location
---@field name Identifier
---@field value NormExpression
local NRecordField = {}
NRecordField.__index = NRecordField

---@param location Location
---@param name Identifier
---@param value NormExpression
---@return NRecordField
function NRecordField.new(location, name, value)
    return setmetatable({
        location = location,
        name = name,
        value = value,
    }, NRecordField)
end

---@class NRecord : NormExpression
---@field kind "NRecord"
---@field location Location
---@field fields NRecordField[]
local NRecord = setmetatable({}, { __index = NormExpression })
NRecord.__index = NRecord

---@param location Location
---@param fields NRecordField[]
---@return NRecord
function NRecord.new(location, fields)
    return setmetatable({
        kind = "NRecord",
        location = location,
        fields = fields or {},
    }, NRecord)
end

---@param f fun(stmt: NormStatement)
function NRecord:iterate(f)
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
function NRecord:flattenLambdas(parentName, m, locals)
    for _, fld in ipairs(self.fields) do
        fld.value = fld.value:flattenLambdas(parentName, m, locals)
    end
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NRecord:replaceLocals(replace)
    for _, fld in ipairs(self.fields) do
        fld.value = fld.value:replaceLocals(replace)
    end
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NRecord:extractUsedLocalsSet(definedLocals, usedLocals)
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
function NRecord:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    local TyRecord = recordMod.TyRecord
    local TyRecordField = recordMod.TyRecordField
    ---@type table[]
    local fields = {}
    for i, f in ipairs(self.fields) do
        local value, err = f.value:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast value -nil
        fields[i] = TyRecordField.new(ctx, self.location, f.name, value)
    end
    return self:setSuccessor(TyRecord.new(ctx, self.location, fields))
end

return { NRecord = NRecord, NRecordField = NRecordField }
