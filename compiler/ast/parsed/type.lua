local Statement = require("compiler.ast.parsed.defines").Statement

---@class Type : Statement
---@field kind string
---@field location Location
---@field successor any|nil
local Type = setmetatable({}, { __index = Statement })
Type.__index = Type

return { Type = Type }
