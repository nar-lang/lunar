---@alias NormPatternMap table<Identifier, table>

---@class NormStatement
---@field kind string
---@field location Location
local NormStatement = {}
NormStatement.__index = NormStatement

---@param f fun(stmt: NormStatement)
function NormStatement:iterate(f)
    error("abstract method 'iterate' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param offset integer
---@return string
function NormStatement:stringTree(offset)
    local treePrint = require("compiler.ast.normalized.tree_print")
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
