local NormType = require("lunar.compiler.ast.normalized.type").NormType
local TyRecordType = require("lunar.compiler.ast.typed.type_record").TyRecordType

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

---@param ctx SolvingContext
---@param params TypeParamsMap
---@param source boolean
---@param placeholders PlaceholderMap|nil
---@return TypedType|nil t
---@return string|nil err
function NTRecord:annotate(ctx, params, source, placeholders)
    ---@type table<Identifier, TypedType>
    local fields = {}
    for n, v in pairs(self.fields) do
        if v == nil then
            return nil, "record field type is not declared"
        end
        local x, err = v:annotate(ctx, params, source, placeholders)
        if err ~= nil then
            return nil, err
        end
        ---@cast x -nil
        fields[n] = x
    end
    return self:setSuccessor(TyRecordType.new(self.location, fields, false))
end

return { NTRecord = NTRecord }
