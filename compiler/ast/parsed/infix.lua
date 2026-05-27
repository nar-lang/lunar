local Statement = require("lunar.compiler.ast.parsed.defines").Statement

---@enum Associativity
local Associativity = {
    NONE = 0,
    LEFT = 1,
    RIGHT = 2,
}

---@class Infix : Statement
---@field kind "Infix"
---@field location Location
---@field hidden boolean
---@field name InfixIdentifier
---@field associativity Associativity
---@field precedence integer
---@field aliasLocation Location
---@field alias Identifier
---@field docComment DocComment|nil
local Infix = setmetatable({}, { __index = Statement })
Infix.__index = Infix

---@param location Location
---@param hidden boolean
---@param name InfixIdentifier
---@param associativity Associativity
---@param precedence integer
---@param aliasLocation Location
---@param alias Identifier
---@return Infix
function Infix.new(location, hidden, name, associativity, precedence, aliasLocation, alias)
    return setmetatable({
        kind = "Infix",
        location = location,
        hidden = hidden == true,
        name = name,
        associativity = associativity,
        precedence = precedence,
        aliasLocation = aliasLocation,
        alias = alias,
        docComment = nil,
    }, Infix)
end

---@param other Infix
---@return boolean
function Infix:hasLowerPrecedenceThan(other)
    if self.precedence < other.precedence then
        return true
    end
    if self.precedence == other.precedence then
        return self.associativity == Associativity.LEFT
    end
    return false
end

---@param f fun(stmt: Statement)
function Infix:iterate(f)
    f(self)
end

return { Infix = Infix, Associativity = Associativity }
