local treePrint = require("compiler.ast.typed.tree_print")
---@alias TypedLocalTypesMap table<Identifier, TypedType>

---@class TypedStatement
---@field kind string
---@field location Location
local TypedStatement = {}
TypedStatement.__index = TypedStatement

---@param offset integer
---@return string
function TypedStatement:stringTree(offset)
    return treePrint.stringTree(self, offset or 0)
end

return {
    TypedStatement = TypedStatement,
}
