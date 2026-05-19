local Expression = require("compiler.ast.parsed.expression").Expression

---@class Var : Expression
---@field kind "Var"
---@field location Location
---@field name QualifiedIdentifier
local Var = setmetatable({}, { __index = Expression })
Var.__index = Var

---@param location Location
---@param name QualifiedIdentifier
---@return Var
function Var.new(location, name)
    return setmetatable({
        kind = "Var",
        location = location,
        name = name,
    }, Var)
end

---@param f fun(stmt: Statement)
function Var:iterate(f)
    f(self)
end

---@return nil
---@return string
function Var:normalize()
    return nil, "TODO: normalize"
end

return { Var = Var }
