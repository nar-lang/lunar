local Expression = require("lunar.compiler.ast.parsed.expression").Expression
local NApply = require("lunar.compiler.ast.normalized.expression_apply").NApply
local NGlobal = require("lunar.compiler.ast.normalized.expression_global").NGlobal
local builtins = require("lunar.compiler.common.builtins")

---@class Negate : Expression
---@field kind "Negate"
---@field location Location
---@field nested Expression
local Negate = setmetatable({}, { __index = Expression })
Negate.__index = Negate

---@param location Location
---@param nested Expression
---@return Negate
function Negate.new(location, nested)
    return setmetatable({
        kind = "Negate",
        location = location,
        nested = nested,
    }, Negate)
end

---@param f fun(stmt: Statement)
function Negate:iterate(f)
    f(self)
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Negate:normalize(locals, modules, module, normalizedModule)
    local nested, err = self.nested:normalize(locals, modules, module, normalizedModule)
    if nested == nil then
        return nil, err
    end
    return self:setSuccessor(NApply.new(
        self.location,
        NGlobal.new(self.location, builtins.NarBaseMathName, builtins.NarNegName),
        { nested })), nil
end

return { Negate = Negate }
