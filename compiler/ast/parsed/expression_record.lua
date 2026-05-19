---@class RecordField
---@field location Location
---@field name Identifier
---@field value Expression
local RecordField = {}
RecordField.__index = RecordField

---@param location Location
---@param name Identifier
---@param value Expression
---@return RecordField
function RecordField.new(location, name, value)
    return setmetatable({
        location = location,
        name = name,
        value = value,
    }, RecordField)
end

local Expression = require("compiler.ast.parsed.expression").Expression

---@class Record : Expression
---@field kind "Record"
---@field location Location
---@field fields RecordField[]
local Record = setmetatable({}, { __index = Expression })
Record.__index = Record

---@param location Location
---@param fields RecordField[]
---@return Record
function Record.new(location, fields)
    return setmetatable({
        kind = "Record",
        location = location,
        fields = fields or {},
    }, Record)
end

---@param f fun(stmt: Statement)
function Record:iterate(f)
    f(self)
    for _, field in ipairs(self.fields) do
        if field.value ~= nil then
            field.value:iterate(f)
        end
    end
end

---@return nil
---@return string
function Record:normalize()
    return nil, "TODO: normalize"
end

return { Record = Record, RecordField = RecordField }
