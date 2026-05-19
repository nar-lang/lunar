local Pattern = require("compiler.ast.parsed.pattern").Pattern
local NPAlias = require("compiler.ast.normalized.pattern_alias").NPAlias
local joinErrors = require("compiler.ast.parsed.defines").joinErrors

---@class PAlias : Pattern
---@field kind "PAlias"
---@field location Location
---@field alias Identifier
---@field nested Pattern
---@field declaredType Type|nil
local PAlias = setmetatable({}, { __index = Pattern })
PAlias.__index = PAlias

---@param location Location
---@param alias Identifier
---@param nested Pattern
---@return PAlias
function PAlias.new(location, alias, nested)
    return setmetatable({
        kind = "PAlias",
        location = location,
        alias = alias,
        nested = nested,
    }, PAlias)
end

---@param f fun(stmt: Statement)
function PAlias:iterate(f)
    f(self)
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormPattern|nil
---@return string|nil error
function PAlias:normalize(locals, modules, module, normalizedModule)
    local nested, err1 = self.nested:normalize(locals, modules, module, normalizedModule)
    if nested == nil then
        return nil, err1 or "failed to normalize nested pattern"
    end
    ---@type NormType|nil
    local declaredType
    ---@type string|nil
    local err2
    if self.declaredType ~= nil then
        declaredType, err2 = self.declaredType:normalize(modules, module, nil)
    end
    local np = NPAlias.new(self.location, declaredType, self.alias, nested)
    locals[self.alias] = np
    return self:setSuccessor(np), joinErrors(err1, err2)
end

return { PAlias = PAlias }
