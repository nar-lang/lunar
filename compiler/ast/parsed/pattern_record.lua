---@class PRecordField
---@field location Location
---@field name Identifier
local PRecordField = {}
PRecordField.__index = PRecordField

---@param location Location
---@param name Identifier
---@return PRecordField
function PRecordField.new(location, name)
    return setmetatable({
        location = location,
        name = name,
    }, PRecordField)
end

local Pattern = require("compiler.ast.parsed.pattern").Pattern

---@class PRecord : Pattern
---@field kind "PRecord"
---@field location Location
---@field fields PRecordField[]
---@field declaredType Type|nil
local PRecord = setmetatable({}, { __index = Pattern })
PRecord.__index = PRecord

---@param location Location
---@param fields PRecordField[]
---@return PRecord
function PRecord.new(location, fields)
    return setmetatable({
        kind = "PRecord",
        location = location,
        fields = fields or {},
    }, PRecord)
end

---@param f fun(stmt: Statement)
function PRecord:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@return nil
---@return string
function PRecord:normalize()
    return nil, "TODO: normalize"
end

return { PRecord = PRecord, PRecordField = PRecordField }
