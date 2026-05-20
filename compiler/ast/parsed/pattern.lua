local Statement = require("lunar.compiler.ast.parsed.defines").Statement

---@class Pattern : Statement
---@field kind string
---@field location Location
---@field declaredType Type|nil
---@field successor any|nil
local Pattern = setmetatable({}, { __index = Statement })
Pattern.__index = Pattern

---Store the normalized result of this parsed node and return it (chaining helper).
---@generic T
---@param n T
---@return T
function Pattern:setSuccessor(n)
    self.successor = n
    return n
end

---Lower this parsed pattern into its normalized counterpart.
---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormPattern|nil
---@return string|nil error
function Pattern:normalize(locals, modules, module, normalizedModule)
    error("abstract method 'normalize' not implemented for kind=" .. tostring(self.kind), 2)
end

return { Pattern = Pattern }
