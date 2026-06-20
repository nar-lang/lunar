local Type = require("lunar.compiler.ast.parsed.type").Type
local NTParameter = require("lunar.compiler.ast.normalized.type_parameter").NTParameter
local utils = require("lunar.compiler.ast.parsed.utils")

---@class TParameter : Type
---@field kind "TParameter"
---@field location Location
---@field name Identifier
local TParameter = setmetatable({}, { __index = Type })
TParameter.__index = TParameter

---@param location Location
---@param name Identifier
---@return TParameter
function TParameter.new(location, name)
    return setmetatable({
        kind = "TParameter",
        location = location,
        name = name,
    }, TParameter)
end

---@param f fun(stmt: Statement)
function TParameter:iterate(f)
    f(self)
end

---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param namedTypes NamedTypeMap|nil
---@return NormType|nil
---@return string|nil error
function TParameter:normalize(modules, module, namedTypes)
    return self:setSuccessor(NTParameter.new(self.location, self.name)), nil
end

---@param params table<Identifier, Type>
---@param loc Location
---@return Type|nil
---@return string|nil error
function TParameter:applyArgs(params, loc)
    local p = params[self.name]
    if p == nil then
        return nil, utils.locErr(loc or self.location, string.format("missing type parameter %s", self.name))
    end
    return p, nil
end

return { TParameter = TParameter }
