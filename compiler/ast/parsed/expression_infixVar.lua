local Expression = require("compiler.ast.parsed.expression").Expression

---@class InfixVar : Expression
---@field kind "InfixVar"
---@field location Location
---@field infix InfixIdentifier
local InfixVar = setmetatable({}, { __index = Expression })
InfixVar.__index = InfixVar

---@param location Location
---@param infix InfixIdentifier
---@return InfixVar
function InfixVar.new(location, infix)
    return setmetatable({
        kind = "InfixVar",
        location = location,
        infix = infix,
    }, InfixVar)
end

---@param f fun(stmt: Statement)
function InfixVar:iterate(f)
    f(self)
end

---@return nil
---@return string
function InfixVar:normalize()
    return nil, "TODO: normalize"
end

return { InfixVar = InfixVar }
