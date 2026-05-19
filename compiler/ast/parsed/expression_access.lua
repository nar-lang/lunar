local Expression = require("compiler.ast.parsed.expression").Expression

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

---@return nil
---@return string
function Access:normalize()
    return nil, "TODO: normalize"
end

return { Access = Access }
