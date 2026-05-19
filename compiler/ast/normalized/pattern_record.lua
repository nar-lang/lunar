local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPRecordField
---@field location Location
---@field name Identifier
local NPRecordField = {}
NPRecordField.__index = NPRecordField

---@param location Location
---@param name Identifier
---@return NPRecordField
function NPRecordField.new(location, name)
    return setmetatable({
        location = location,
        name = name,
    }, NPRecordField)
end

---@class NPRecord : NormPattern
---@field kind "NPRecord"
---@field location Location
---@field declaredType NormType|nil
---@field fields NPRecordField[]
local NPRecord = setmetatable({}, { __index = NormPattern })
NPRecord.__index = NPRecord

---@param location Location
---@param declaredType NormType|nil
---@param fields NPRecordField[]
---@return NPRecord
function NPRecord.new(location, declaredType, fields)
    return setmetatable({
        kind = "NPRecord",
        location = location,
        declaredType = declaredType,
        fields = fields or {},
    }, NPRecord)
end

---@param f fun(stmt: NormStatement)
function NPRecord:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals NormPatternMap
function NPRecord:extractLocals(locals)
    for _, fld in ipairs(self.fields) do
        locals[fld.name] = self
    end
end

return { NPRecord = NPRecord, NPRecordField = NPRecordField }
