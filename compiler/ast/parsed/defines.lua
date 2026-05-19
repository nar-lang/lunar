---@alias NamedTypeMap table<FullIdentifier, any>

---@class Statement
---@field kind string
---@field location Location
local Statement = {}
Statement.__index = Statement

---Iterate this statement and its children. Concrete subclasses must override.
---@param f fun(stmt: Statement)
function Statement:iterate(f)
    error("abstract method 'iterate' not implemented for kind=" .. tostring(self.kind), 2)
end

---Normalize this statement. Concrete subclasses must override.
---@return any|nil normalized
---@return string|nil error
function Statement:normalize()
    error("abstract method 'normalize' not implemented for kind=" .. tostring(self.kind), 2)
end

---Render this node and all of its descendants as a single multi-line string.
---One line per node, indented with `\t * offset`.
---@param offset integer
---@return string
function Statement:stringTree(offset)
    local treePrint = require("compiler.ast.parsed.tree_print")
    return treePrint.stringTree(self, offset or 0)
end

return { Statement = Statement }
