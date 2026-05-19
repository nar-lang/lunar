local Expression = require("compiler.ast.parsed.expression").Expression

---@class Const : Expression
---@field kind "Const"
---@field location Location
---@field value ConstValue
local Const = setmetatable({}, { __index = Expression })
Const.__index = Const

---@param location Location
---@param value ConstValue
---@return Const
function Const.new(location, value)
    return setmetatable({
        kind = "Const",
        location = location,
        value = value,
    }, Const)
end

---@param f fun(stmt: Statement)
function Const:iterate(f)
    f(self)
end

---@return nil
---@return string
function Const:normalize()
    return nil, "TODO: normalize"
end

return { Const = Const }
