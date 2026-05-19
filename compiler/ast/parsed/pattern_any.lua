local Pattern = require("compiler.ast.parsed.pattern").Pattern
local NPAny = require("compiler.ast.normalized.pattern_any").NPAny

---@class PAny : Pattern
---@field kind "PAny"
---@field location Location
---@field declaredType Type|nil
local PAny = setmetatable({}, { __index = Pattern })
PAny.__index = PAny

---@param location Location
---@return PAny
function PAny.new(location)
    return setmetatable({
        kind = "PAny",
        location = location,
    }, PAny)
end

---@param f fun(stmt: Statement)
function PAny:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormPattern
---@return string|nil error
function PAny:normalize(locals, modules, module, normalizedModule)
    ---@type NormType|nil
    local declaredType
    ---@type string|nil
    local err
    if self.declaredType ~= nil then
        declaredType, err = self.declaredType:normalize(modules, module, nil)
    end
    return self:setSuccessor(NPAny.new(self.location, declaredType)), err
end

return { PAny = PAny }
