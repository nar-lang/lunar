local Statement = require("lunar.compiler.ast.parsed.defines").Statement

---@class Type : Statement
---@field kind string
---@field location Location
---@field successor any|nil
local Type = setmetatable({}, { __index = Statement })
Type.__index = Type

---Store the normalized result of this parsed node and return it (chaining helper).
---@generic T
---@param n T
---@return T
function Type:setSuccessor(n)
    self.successor = n
    return n
end

---Lower this parsed type into its normalized counterpart.
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param namedTypes NamedTypeMap|nil
---@return NormType|nil
---@return string|nil error
function Type:normalize(modules, module, namedTypes)
    error("abstract method 'normalize' not implemented for kind=" .. tostring(self.kind), 2)
end

---Substitute type parameters in this type with the supplied mapping.
---@param params table<Identifier, Type>
---@param loc Location
---@return Type|nil
---@return string|nil error
function Type:applyArgs(params, loc)
    error("abstract method 'applyArgs' not implemented for kind=" .. tostring(self.kind), 2)
end

return { Type = Type }
