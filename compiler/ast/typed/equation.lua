---Type equation: assertion that two types should unify.

---@class Equation
---@field left TypedType
---@field right TypedType
---@field stmt TypedStatement
local Equation = {}
Equation.__index = Equation

---Pick the most specific statement to attach the equation to: prefer the
---one whose location is contained by `enclosing`. Fallback to creating a
---synthetic "---" definition that owns `enclosing`.
---@param left TypedType
---@param right TypedType
---@param enclosing Location
---@return Equation
local function newEquationBestLoc(left, right, enclosing)
    ---@type TypedStatement
    local stmt
    local leftLoc = left.location
    local rightLoc = right.location
    if enclosing and enclosing.contains and enclosing:contains(leftLoc) then
        stmt = left
    elseif enclosing and enclosing.contains and enclosing:contains(rightLoc) then
        stmt = right
    else
        local TypedDefinition = require("compiler.ast.typed.definition").TypedDefinition
        stmt = TypedDefinition.new(enclosing, 0, false, "---", enclosing)
    end
    return setmetatable({
        left = left,
        right = right,
        stmt = stmt,
    }, Equation)
end

---@param stmt TypedStatement
---@param left TypedType
---@param right TypedType
---@return Equation
local function newEquation(stmt, left, right)
    return setmetatable({
        stmt = stmt,
        left = left,
        right = right,
    }, Equation)
end

---@param other Equation
---@return boolean
function Equation:equalsTo(other)
    return (self.left:equalsTo(other.left, nil) and self.right:equalsTo(other.right, nil)) or
        (self.right:equalsTo(other.left, nil) and self.left:equalsTo(other.right, nil))
end

---@return boolean
function Equation:isRedundant()
    return self.left:equalsTo(self.right, nil)
end

---Filter useful equations: drop redundant + duplicates already present in
---`eqs`. Returns mutated `eqs`.
---@param eqs Equation[]
---@param extra Equation[]
---@return Equation[]
local function appendUsefulEquations(eqs, extra)
    if extra == nil then
        return eqs
    end
    for _, eq in ipairs(extra) do
        if not eq:isRedundant() then
            local dup = false
            for _, x in ipairs(eqs) do
                if x:equalsTo(eq) then
                    dup = true
                    break
                end
            end
            if not dup then
                eqs[#eqs + 1] = eq
            end
        end
    end
    return eqs
end

return {
    Equation = Equation,
    newEquation = newEquation,
    newEquationBestLoc = newEquationBestLoc,
    appendUsefulEquations = appendUsefulEquations,
}
