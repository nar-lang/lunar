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

local Expression = require("lunar.compiler.ast.parsed.expression").Expression
local NRecord = require("lunar.compiler.ast.normalized.expression_record").NRecord
local NRecordField = require("lunar.compiler.ast.normalized.expression_record").NRecordField

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

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Record:normalize(locals, modules, module, normalizedModule)
    local fields = {}
    for i, field in ipairs(self.fields) do
        local nValue, err = field.value:normalize(locals, modules, module, normalizedModule)
        if nValue == nil then
            return nil, err
        end
        fields[i] = NRecordField.new(field.location, field.name, nValue)
    end
    return self:setSuccessor(NRecord.new(self.location, fields)), nil
end

return { Record = Record, RecordField = RecordField }
