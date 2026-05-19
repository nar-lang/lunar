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
local NPRecord = require("compiler.ast.normalized.pattern_record").NPRecord
local NPRecordField = require("compiler.ast.normalized.pattern_record").NPRecordField
local NPNamed = require("compiler.ast.normalized.pattern_named").NPNamed

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

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormPattern
---@return string|nil error
function PRecord:normalize(locals, modules, module, normalizedModule)
    ---@type NormType|nil
    local declaredType
    ---@type string|nil
    local err
    if self.declaredType ~= nil then
        declaredType, err = self.declaredType:normalize(modules, module, nil)
    end
    local fields = {}
    for i, x in ipairs(self.fields) do
        locals[x.name] = NPNamed.new(x.location, nil, x.name)
        fields[i] = NPRecordField.new(x.location, x.name)
    end
    return self:setSuccessor(NPRecord.new(self.location, declaredType, fields)), err
end

return { PRecord = PRecord, PRecordField = PRecordField }
