local treePrint = require("compiler.ast.normalized.tree_print")
---@alias NormPatternMap table<Identifier, table>
---@alias TypeParamsMap table<Identifier, TypedType>
---@alias PlaceholderMap table<FullIdentifier, TypedType>

---@class NormStatement
---@field kind string
---@field location Location
---@field successor TypedStatement|nil
local NormStatement = {}
NormStatement.__index = NormStatement

---@param f fun(stmt: NormStatement)
function NormStatement:iterate(f)
    error("abstract method 'iterate' not implemented for kind=" .. tostring(self.kind), 2)
end

---Set the typed successor for this normalized node and return it.
---@generic T
---@param typed T
---@return T
function NormStatement:setSuccessor(typed)
    self.successor = typed
    return typed
 end

---@param offset integer
---@return string
function NormStatement:stringTree(offset)
    return treePrint.stringTree(self, offset or 0)
end

---Module-scoped counters that mirror the package-level state in Go.
local Counters = {
    lastDefinitionId = 0,
    lastLambdaId = 0,
}

return {
    NormStatement = NormStatement,
    Counters = Counters,
}
