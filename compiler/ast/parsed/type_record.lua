local Type = require("lunar.compiler.ast.parsed.type").Type
local NTRecord = require("lunar.compiler.ast.normalized.type_record").NTRecord

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

---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param namedTypes NamedTypeMap|nil
---@return NormType|nil
---@return string|nil error
function TRecord:normalize(modules, module, namedTypes)
    local fields = {}
    for name, v in pairs(self.fields) do
        local nv, err = v:normalize(modules, module, namedTypes)
        if err ~= nil then
            return nil, err
        end
        ---@cast nv -nil
        fields[name] = nv
    end
    return self:setSuccessor(NTRecord.new(self.location, fields)), nil
end

---@param params table<Identifier, Type>
---@param loc Location
---@return Type|nil
---@return string|nil error
function TRecord:applyArgs(params, loc)
    local fields = {}
    for name, f in pairs(self.fields) do
        local nf, err = f:applyArgs(params, loc)
        if err ~= nil then
            return nil, err
        end
        ---@cast nf -nil
        fields[name] = nf
    end
    return TRecord.new(loc, fields), nil
end

return { TRecord = TRecord }
