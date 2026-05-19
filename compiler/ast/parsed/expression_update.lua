local Expression = require("compiler.ast.parsed.expression").Expression

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

---@return nil
---@return string
function Update:normalize()
    return nil, "TODO: normalize"
end

return { Update = Update }
