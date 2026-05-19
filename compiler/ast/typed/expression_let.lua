local TypedExpression = require("compiler.ast.typed.expression").TypedExpression
local newEquation = require("compiler.ast.typed.equation").newEquation
local bytecode = require("compiler.bytecode.op")

---@class TyLet : TypedExpression
---@field kind "TyLet"
---@field location Location
---@field type_ TypedType
---@field pattern TypedPattern
---@field value TypedExpression
---@field body TypedExpression
local TyLet = setmetatable({}, { __index = TypedExpression })
TyLet.__index = TyLet

---@param ctx SolvingContext
---@param loc Location
---@param pattern TypedPattern
---@param value TypedExpression
---@param body TypedExpression
---@return TyLet
function TyLet.new(ctx, loc, pattern, value, body)
    local e = setmetatable({
        kind = "TyLet",
        location = loc,
        type_ = nil,
        pattern = pattern,
        value = value,
        body = body,
    }, TyLet)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyLet:checkPatterns()
    local utils = require("compiler.ast.typed.utils")
    local err = utils.checkPattern(self.pattern)
    if err ~= nil then
        return err
    end
    err = self.value:checkPatterns()
    if err ~= nil then
        return err
    end
    return self.body:checkPatterns()
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyLet:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    err = self.pattern:mapTypes(subst)
    if err ~= nil then
        return err
    end
    err = self.value:mapTypes(subst)
    if err ~= nil then
        return err
    end
    return self.body:mapTypes(subst)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyLet:code(currentModule)
    return string.format("let %s = %s in %s",
        self.pattern:code(currentModule),
        self.value:code(currentModule),
        self.body:code(currentModule))
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyLet:appendEquations(eqs, loc, localDefs, ctx, stack)
    eqs[#eqs + 1] = newEquation(self, self.type_, self.body:getType())
    local newEqs, err = self.pattern:appendEquations(eqs, loc, localDefs, ctx, stack)
    if err ~= nil then
        return nil, err
    end
    newEqs, err = self.value:appendEquations(newEqs, loc, localDefs, ctx, stack)
    if err ~= nil then
        return nil, err
    end
    newEqs[#newEqs + 1] = newEquation(self, self.pattern:getType(), self.value:getType())
    newEqs, err = self.body:appendEquations(newEqs, loc, localDefs, ctx, stack)
    if err ~= nil then
        return nil, err
    end
    return newEqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyLet:appendBytecode(ops, locations, binary, hash)
    ops, locations = self.value:appendBytecode(ops, locations, binary, hash)
    ops, locations = self.pattern:appendBytecode(ops, locations, binary, hash)
    ops, locations = bytecode.appendJump(0, true, self.location, ops, locations)
    ops, locations = bytecode.appendSwapPop(self.location, bytecode.SWAP_POP_MODE_POP, ops, locations)
    return self.body:appendBytecode(ops, locations, binary, hash)
end

return { TyLet = TyLet }
