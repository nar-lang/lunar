local Expression = require("compiler.ast.parsed.expression").Expression
local NAccess = require("compiler.ast.normalized.expression_access").NAccess

---@class Access : Expression
---@field kind "Access"
---@field location Location
---@field record Expression
---@field fieldName Identifier
---@field fieldNameLocation Location
local Access = setmetatable({}, { __index = Expression })
Access.__index = Access

---@param location Location
---@param record Expression
---@param fieldName Identifier
---@param fieldNameLocation Location
---@return Access
function Access.new(location, record, fieldName, fieldNameLocation)
    return setmetatable({
        kind = "Access",
        location = location,
        record = record,
        fieldName = fieldName,
        fieldNameLocation = fieldNameLocation,
    }, Access)
end

---@param f fun(stmt: Statement)
function Access:iterate(f)
    f(self)
    if self.record ~= nil then
        self.record:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Access:normalize(locals, modules, module, normalizedModule)
    local record, err = self.record:normalize(locals, modules, module, normalizedModule)
    if record == nil then
        return nil, err
    end
    return self:setSuccessor(NAccess.new(self.location, record, self.fieldName)), nil
end

return { Access = Access }
