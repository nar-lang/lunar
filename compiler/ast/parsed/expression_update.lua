local Expression = require("lunar.compiler.ast.parsed.expression").Expression
local NUpdate = require("lunar.compiler.ast.normalized.expression_update").NUpdate
local NRecordField = require("lunar.compiler.ast.normalized.expression_record").NRecordField
local utils = require("lunar.compiler.ast.parsed.utils")

---@class Update : Expression
---@field kind "Update"
---@field location Location
---@field recordName QualifiedIdentifier
---@field fields RecordField[]
local Update = setmetatable({}, { __index = Expression })
Update.__index = Update

---@param location Location
---@param recordName QualifiedIdentifier
---@param fields RecordField[]
---@return Update
function Update.new(location, recordName, fields)
    return setmetatable({
        kind = "Update",
        location = location,
        recordName = recordName,
        fields = fields or {},
    }, Update)
end

---@param f fun(stmt: Statement)
function Update:iterate(f)
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
function Update:normalize(locals, modules, module, normalizedModule)
    local fields = {}
    for i, field in ipairs(self.fields) do
        local value, err = field.value:normalize(locals, modules, module, normalizedModule)
        if value == nil then
            return nil, err
        end
        fields[i] = NRecordField.new(field.location, field.name, value)
    end
    local d, m, ids = module:findDefinitionAndAddDependency(modules, self.recordName, normalizedModule)
    if ids ~= nil and #ids == 1 then
        ---@cast d Definition
        ---@cast m Module
        return NUpdate.newGlobal(self.location, m.name, d.name, fields), nil
    elseif ids ~= nil and #ids > 1 then
        return nil, utils.newAmbiguousDefinitionError(ids, self.recordName, self.location)
    end
    ---@type Identifier
    local localKey = self.recordName
    local lc = locals[localKey]
    if lc ~= nil then
        return self:setSuccessor(NUpdate.newLocal(self.location, localKey, lc, fields)), nil
    end
    return nil, string.format("identifier `%s` not found", self.recordName)
end

return { Update = Update }
