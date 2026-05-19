local NormType = require("compiler.ast.normalized.type").NormType

---@class NTRecord : NormType
---@field kind "NTRecord"
---@field location Location
---@field fields table<Identifier, NormType>
local NTRecord = setmetatable({}, { __index = NormType })
NTRecord.__index = NTRecord

---@param location Location
---@param fields table<Identifier, NormType>
---@return NTRecord
function NTRecord.new(location, fields)
    return setmetatable({
        kind = "NTRecord",
        location = location,
        fields = fields or {},
    }, NTRecord)
end

---@param f fun(stmt: NormStatement)
function NTRecord:iterate(f)
    f(self)
    for _, v in pairs(self.fields) do
        if v ~= nil then
            v:iterate(f)
        end
    end
end

return { NTRecord = NTRecord }
