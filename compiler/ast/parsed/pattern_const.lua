local Pattern = require("compiler.ast.parsed.pattern").Pattern
local NPConst = require("compiler.ast.normalized.pattern_const").NPConst

---@class PConst : Pattern
---@field kind "PConst"
---@field location Location
---@field value ConstValue
---@field declaredType Type|nil
local PConst = setmetatable({}, { __index = Pattern })
PConst.__index = PConst

---@param location Location
---@param value ConstValue
---@return PConst
function PConst.new(location, value)
    return setmetatable({
        kind = "PConst",
        location = location,
        value = value,
    }, PConst)
end

---@param f fun(stmt: Statement)
function PConst:iterate(f)
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
function PConst:normalize(locals, modules, module, normalizedModule)
    ---@type NormType|nil
    local declaredType
    ---@type string|nil
    local err
    if self.declaredType ~= nil then
        declaredType, err = self.declaredType:normalize(modules, module, nil)
    end
    return self:setSuccessor(NPConst.new(self.location, declaredType, self.value)), err
end

return { PConst = PConst }
