local NormStatement = require("compiler.ast.normalized.defines").NormStatement

---@class NormType : NormStatement
---@field kind string
---@field location Location
local NormType = setmetatable({}, { __index = NormStatement })
NormType.__index = NormType

return { NormType = NormType }
