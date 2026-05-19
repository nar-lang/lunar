local Statement = require("compiler.ast.parsed.defines").Statement

---@class Expression : Statement
---@field kind string
---@field location Location
---@field successor any|nil
local Expression = setmetatable({}, { __index = Statement })
Expression.__index = Expression

---Store the normalized result of this parsed node and return it (chaining helper).
---@generic T
---@param n T
---@return T
function Expression:setSuccessor(n)
    self.successor = n
    return n
end

---Lower this parsed expression into its normalized counterpart.
---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Expression:normalize(locals, modules, module, normalizedModule)
    error("abstract method 'normalize' not implemented for kind=" .. tostring(self.kind), 2)
end

return { Expression = Expression }
