local Expression = require("compiler.ast.parsed.expression").Expression
local NConst = require("compiler.ast.normalized.expression_const").NConst

---@class Const : Expression
---@field kind "Const"
---@field location Location
---@field value ConstValue
local Const = setmetatable({}, { __index = Expression })
Const.__index = Const

---@param location Location
---@param value ConstValue
---@return Const
function Const.new(location, value)
    return setmetatable({
        kind = "Const",
        location = location,
        value = value,
    }, Const)
end

---@param f fun(stmt: Statement)
function Const:iterate(f)
    f(self)
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression
---@return string|nil error
function Const:normalize(locals, modules, module, normalizedModule)
    return self:setSuccessor(NConst.new(self.location, self.value)), nil
end

return { Const = Const }
