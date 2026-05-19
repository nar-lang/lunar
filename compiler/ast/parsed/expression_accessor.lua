local Expression = require("compiler.ast.parsed.expression").Expression

---@class Accessor : Expression
---@field kind "Accessor"
---@field location Location
---@field fieldName Identifier
local Accessor = setmetatable({}, { __index = Expression })
Accessor.__index = Accessor

---@param location Location
---@param fieldName Identifier
---@return Accessor
function Accessor.new(location, fieldName)
    return setmetatable({
        kind = "Accessor",
        location = location,
        fieldName = fieldName,
    }, Accessor)
end

---@param f fun(stmt: Statement)
function Accessor:iterate(f)
    f(self)
end

---@return nil
---@return string
function Accessor:normalize()
    return nil, "TODO: normalize"
end

return { Accessor = Accessor }
