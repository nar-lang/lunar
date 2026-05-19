local Statement = require("compiler.ast.parsed.defines").Statement

---@class Expression : Statement
---@field kind string
---@field location Location
---@field successor any|nil
local Expression = setmetatable({}, { __index = Statement })
Expression.__index = Expression

return { Expression = Expression }
