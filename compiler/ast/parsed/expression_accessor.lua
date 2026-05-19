local Expression = require("compiler.ast.parsed.expression").Expression
local Lambda = require("compiler.ast.parsed.expression_lambda").Lambda
local PNamed = require("compiler.ast.parsed.pattern_named").PNamed
local Var = require("compiler.ast.parsed.expression_var").Var
local Access = require("compiler.ast.parsed.expression_access").Access

---@class Accessor : Expression
---@field kind "Accessor"
---@field location Location
---@field fieldName Identifier
local Accessor = setmetatable({}, { __index = Expression })
Accessor.__index = Accessor

---@param location Location
---@param fieldName Identifier
---@return Accessor
function Accessor.new(location, fieldName)
    return setmetatable({
        kind = "Accessor",
        location = location,
        fieldName = fieldName,
    }, Accessor)
end

---@param f fun(stmt: Statement)
function Accessor:iterate(f)
    f(self)
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Accessor:normalize(locals, modules, module, normalizedModule)
    ---@type Expression
    local lambda = Lambda.new(
        self.location,
        { PNamed.new(self.location, "x", self.location) },
        nil,
        Access.new(self.location, Var.new(self.location, "x"), self.fieldName, self.location))
    local nLambda, err = lambda:normalize(locals, modules, module, normalizedModule)
    if nLambda == nil then
        return nil, err
    end
    self.successor = nLambda
    return nLambda, nil
end

return { Accessor = Accessor }
