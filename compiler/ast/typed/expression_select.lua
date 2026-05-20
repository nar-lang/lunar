local TypedExpression = require("lunar.compiler.ast.typed.expression").TypedExpression
local newEquation = require("lunar.compiler.ast.typed.equation").newEquation
local bytecode = require("lunar.compiler.bytecode.op")
local utils = require("lunar.compiler.ast.typed.utils")

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
    ---@cast t -nil
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
    ---@cast newEqs -nil
    eqs = newEqs
    for _, cs in ipairs(self.cases) do
        eqs[#eqs + 1] = newEquation(self, self.condition:getType(), cs.pattern:getType())
        eqs[#eqs + 1] = newEquation(self, self.type_, cs.expression:getType())
    end
    for _, cs in ipairs(self.cases) do
        ---@type Equation[]|nil
        local nextEqs
        nextEqs, err = cs.pattern:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast nextEqs -nil
        eqs = nextEqs
        nextEqs, err = cs.expression:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast nextEqs -nil
        eqs = nextEqs
    end
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TySelect:appendBytecode(ops, locations, binary, hash)
    ops, locations = self.condition:appendBytecode(ops, locations, binary, hash)
    ---@type integer[]
    local jumpToEndIndices = {}
    ---@type integer
    local prevMatchOpIndex = 0
    for i, cs in ipairs(self.cases) do
        if i > 1 then
            -- patch the previous case's jump-to-next-case with the now-known offset
            ops[prevMatchOpIndex] = bytecode.withDelta(ops[prevMatchOpIndex], #ops - prevMatchOpIndex)
        end
        ops, locations = cs.pattern:appendBytecode(ops, locations, binary, hash)
        prevMatchOpIndex = #ops + 1
        ops, locations = bytecode.appendJump(0, true, cs.location, ops, locations)
        ops, locations = cs.expression:appendBytecode(ops, locations, binary, hash)
        jumpToEndIndices[#jumpToEndIndices + 1] = #ops + 1
        ops, locations = bytecode.appendJump(0, false, cs.location, ops, locations)
    end
    local selectEndIndex = #ops
    for _, jumpOpIndex in ipairs(jumpToEndIndices) do
        ops[jumpOpIndex] = bytecode.withDelta(ops[jumpOpIndex], selectEndIndex - jumpOpIndex)
    end
    return bytecode.appendSwapPop(self.location, bytecode.SWAP_POP_MODE_BOTH, ops, locations)
end

return {
    TySelect = TySelect,
    TySelectCase = TySelectCase,
}
