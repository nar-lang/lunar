local TypedPattern = require("compiler.ast.typed.pattern").TypedPattern
local newEquation = require("compiler.ast.typed.equation").newEquation
local bytecode = require("compiler.bytecode.op")

---@class TyPAlias : TypedPattern
---@field kind "TyPAlias"
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
---@field alias Identifier
---@field nested TypedPattern
local TyPAlias = setmetatable({}, { __index = TypedPattern })
TyPAlias.__index = TyPAlias

---@param ctx SolvingContext
---@param loc Location
---@param declaredType TypedType|nil
---@param alias Identifier
---@param nested TypedPattern
---@return TyPAlias
function TyPAlias.new(ctx, loc, declaredType, alias, nested)
    local p = setmetatable({
        kind = "TyPAlias",
        location = loc,
        type_ = nil,
        declaredType = declaredType,
        alias = alias,
        nested = nested,
    }, TyPAlias)
    ctx:annotatePattern(p)
    return p
end

---@return SimplePattern
function TyPAlias:simplify()
    return self.nested:simplify()
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyPAlias:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    return self.nested:mapTypes(subst)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyPAlias:code(currentModule)
    local s = string.format("(%s as %s)", self.nested:code(currentModule), self.alias)
    if self.declaredType ~= nil then
        s = s .. ": " .. self.declaredType:code(currentModule)
    end
    return s
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyPAlias:appendEquations(eqs, loc, localDefs, ctx, stack)
    localDefs[self.alias] = self.type_
    local newEqs, err = self.nested:appendEquations(eqs, loc, localDefs, ctx, stack)
    if err ~= nil then
        return nil, err
    end
    newEqs[#newEqs + 1] = newEquation(self, self.type_, self.nested:getType())
    if self.declaredType ~= nil then
        newEqs[#newEqs + 1] = newEquation(self, self.type_, self.declaredType)
    end
    return newEqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyPAlias:appendBytecode(ops, locations, binary, hash)
    ops, locations = self.nested:appendBytecode(ops, locations, binary, hash)
    return bytecode.appendMakePattern(bytecode.PATTERN_KIND_ALIAS, self.alias, 0, self.location, ops, locations, binary, hash)
end

return { TyPAlias = TyPAlias }
