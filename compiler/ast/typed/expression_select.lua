local TypedExpression = require("compiler.ast.typed.expression").TypedExpression
local newEquation = require("compiler.ast.typed.equation").newEquation

---@class TySelectCase
---@field location Location
---@field pattern TypedPattern
---@field expression TypedExpression
local TySelectCase = {}
TySelectCase.__index = TySelectCase

---@param loc Location
---@param pattern TypedPattern
---@param expression TypedExpression
---@return TySelectCase
function TySelectCase.new(loc, pattern, expression)
    return setmetatable({
        location = loc,
        pattern = pattern,
        expression = expression,
    }, TySelectCase)
end

---@class TySelect : TypedExpression
---@field kind "TySelect"
---@field location Location
---@field type_ TypedType
---@field condition TypedExpression
---@field cases TySelectCase[]
local TySelect = setmetatable({}, { __index = TypedExpression })
TySelect.__index = TySelect

---@param ctx SolvingContext
---@param loc Location
---@param condition TypedExpression
---@param cases TySelectCase[]
---@return TySelect
function TySelect.new(ctx, loc, condition, cases)
    local e = setmetatable({
        kind = "TySelect",
        location = loc,
        type_ = nil,
        condition = condition,
        cases = cases or {},
    }, TySelect)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TySelect:checkPatterns()
    local utils = require("compiler.ast.typed.utils")
    local err = self.condition:checkPatterns()
    if err ~= nil then
        return err
    end
    ---@type TypedPattern[]
    local pats = {}
    for i, cs in ipairs(self.cases) do
        pats[i] = cs.pattern
    end
    err = utils.checkPatterns(pats)
    if err ~= nil then
        return err
    end
    for _, cs in ipairs(self.cases) do
        err = cs.expression:checkPatterns()
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TySelect:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    err = self.condition:mapTypes(subst)
    if err ~= nil then
        return err
    end
    for _, cs in ipairs(self.cases) do
        err = cs.pattern:mapTypes(subst)
        if err ~= nil then
            return err
        end
        err = cs.expression:mapTypes(subst)
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TySelect:code(currentModule)
    local parts = {}
    for _, cs in ipairs(self.cases) do
        parts[#parts + 1] = "case " ..
            cs.pattern:code(currentModule) .. " -> " .. cs.expression:code(currentModule)
    end
    return string.format("select %s %s end",
        self.condition:code(currentModule), table.concat(parts, " "))
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TySelect:appendEquations(eqs, loc, localDefs, ctx, stack)
    local newEqs, err = self.condition:appendEquations(eqs, loc, localDefs, ctx, stack)
    if err ~= nil then
        return nil, err
    end
    eqs = newEqs
    for _, cs in ipairs(self.cases) do
        eqs[#eqs + 1] = newEquation(self, self.condition:getType(), cs.pattern:getType())
        eqs[#eqs + 1] = newEquation(self, self.type_, cs.expression:getType())
    end
    for _, cs in ipairs(self.cases) do
        eqs, err = cs.pattern:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
        eqs, err = cs.expression:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
    end
    return eqs, nil
end

return {
    TySelect = TySelect,
    TySelectCase = TySelectCase,
}
