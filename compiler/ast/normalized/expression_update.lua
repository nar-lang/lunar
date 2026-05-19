local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")

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

return { NUpdate = NUpdate }
