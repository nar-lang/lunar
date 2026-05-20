---@alias TypedLocalTypesMap table<Identifier, TypedType>

---@class TypedStatement
---@field kind string
---@field location Location
local TypedStatement = {}
TypedStatement.__index = TypedStatement

return {
    TypedStatement = TypedStatement,
}
