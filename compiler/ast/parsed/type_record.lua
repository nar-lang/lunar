local Type = require("compiler.ast.parsed.type").Type

---@class TRecord : Type
---@field kind "TRecord"
---@field location Location
---@field fields table<Identifier, Type>
local TRecord = setmetatable({}, { __index = Type })
TRecord.__index = TRecord

---@param location Location
---@param fields table<Identifier, Type>
---@return TRecord
function TRecord.new(location, fields)
    return setmetatable({
        kind = "TRecord",
        location = location,
        fields = fields or {},
    }, TRecord)
end

---@param f fun(stmt: Statement)
function TRecord:iterate(f)
    f(self)
    for _, fieldType in pairs(self.fields) do
        if fieldType ~= nil then
            fieldType:iterate(f)
        end
    end
end

---@return nil
---@return string
function TRecord:normalize()
    return nil, "TODO: normalize"
end

return { TRecord = TRecord }
