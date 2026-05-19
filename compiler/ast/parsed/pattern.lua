local Statement = require("compiler.ast.parsed.defines").Statement

---@class Pattern : Statement
---@field kind string
---@field location Location
---@field declaredType Type|nil
---@field successor any|nil
local Pattern = setmetatable({}, { __index = Statement })
Pattern.__index = Pattern

return { Pattern = Pattern }
