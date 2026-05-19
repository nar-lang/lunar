local Type = require("compiler.ast.parsed.type").Type
local NTUnit = require("compiler.ast.normalized.type_unit").NTUnit

---@class TUnit : Type
---@field kind "TUnit"
---@field location Location
local TUnit = setmetatable({}, { __index = Type })
TUnit.__index = TUnit

---@param location Location
---@return TUnit
function TUnit.new(location)
    return setmetatable({
        kind = "TUnit",
        location = location,
    }, TUnit)
end

---@param f fun(stmt: Statement)
function TUnit:iterate(f)
    f(self)
end

---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param namedTypes NamedTypeMap|nil
---@return NormType|nil
---@return string|nil error
function TUnit:normalize(modules, module, namedTypes)
    return self:setSuccessor(NTUnit.new(self.location)), nil
end

---@param params table<Identifier, Type>
---@param loc Location
---@return Type
---@return string|nil error
function TUnit:applyArgs(params, loc)
    return self, nil
end

return { TUnit = TUnit }
