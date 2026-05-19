local NormStatement = require("compiler.ast.normalized.defines").NormStatement

---@class NormPattern : NormStatement
---@field kind string
---@field location Location
---@field declaredType NormType|nil
local NormPattern = setmetatable({}, { __index = NormStatement })
NormPattern.__index = NormPattern

---@param locals NormPatternMap
function NormPattern:extractLocals(locals)
    error("abstract method 'extractLocals' not implemented for kind=" .. tostring(self.kind), 2)
end

return { NormPattern = NormPattern }
