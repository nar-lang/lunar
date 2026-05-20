local Pattern = require("lunar.compiler.ast.parsed.pattern").Pattern
local NPNamed = require("lunar.compiler.ast.normalized.pattern_named").NPNamed

---@class PNamed : Pattern
---@field kind "PNamed"
---@field location Location
---@field name Identifier
---@field nameLocation Location
---@field declaredType Type|nil
local PNamed = setmetatable({}, { __index = Pattern })
PNamed.__index = PNamed

---@param location Location
---@param name Identifier
---@param nameLocation Location
---@return PNamed
function PNamed.new(location, name, nameLocation)
    return setmetatable({
        kind = "PNamed",
        location = location,
        name = name,
        nameLocation = nameLocation,
    }, PNamed)
end

---@param f fun(stmt: Statement)
function PNamed:iterate(f)
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
function PNamed:normalize(locals, modules, module, normalizedModule)
    ---@type NormType|nil
    local declaredType
    ---@type string|nil
    local err
    if self.declaredType ~= nil then
        declaredType, err = self.declaredType:normalize(modules, module, nil)
    end
    local np = NPNamed.new(self.location, declaredType, self.name)
    locals[self.name] = np
    return self:setSuccessor(np), err
end

return { PNamed = PNamed }
