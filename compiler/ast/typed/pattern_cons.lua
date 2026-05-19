local TypedPattern = require("compiler.ast.typed.pattern").TypedPattern
local newEquation = require("compiler.ast.typed.equation").newEquation
local TNative = require("compiler.ast.typed.type_native").TNative
local TData = require("compiler.ast.typed.type_data").TData
local DataOption = require("compiler.ast.typed.type_data").DataOption
local SimpleConstructor = require("compiler.ast.typed.simple_pattern").SimpleConstructor
local builtins = require("compiler.common.builtins")
local bytecode = require("compiler.bytecode.op")

---@class TyPCons : TypedPattern
---@field kind "TyPCons"
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
---@field head TypedPattern
---@field tail TypedPattern
---@field ctx SolvingContext
local TyPCons = setmetatable({}, { __index = TypedPattern })
TyPCons.__index = TyPCons

---@param ctx SolvingContext
---@param loc Location
---@param declaredType TypedType|nil
---@param head TypedPattern
---@param tail TypedPattern
---@return TyPCons
function TyPCons.new(ctx, loc, declaredType, head, tail)
    local p = setmetatable({
        kind = "TyPCons",
        location = loc,
        type_ = nil,
        declaredType = declaredType,
        head = head,
        tail = tail,
        ctx = ctx,
    }, TyPCons)
    ctx:annotatePattern(p)
    return p
end

---@return SimpleConstructor
function TyPCons:simplify()
    local a = self.ctx:newTypeAnnotation(self)
    local head = self.head:simplify()
    local tail = self.tail:simplify()
    local union = TData.new(self.location, "!!list", nil, {
        DataOption.new("Nil", nil),
        DataOption.new("Cons", { a, TNative.new(self.location, builtins.NarBaseListList, { a }) }),
    })
    return SimpleConstructor.new(union, "Cons", { head, tail })
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyPCons:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    err = self.head:mapTypes(subst)
    if err ~= nil then
        return err
    end
    return self.tail:mapTypes(subst)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyPCons:code(currentModule)
    local s = string.format("(%s | %s)", self.head:code(currentModule), self.tail:code(currentModule))
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
function TyPCons:appendEquations(eqs, loc, localDefs, ctx, stack)
    local typeNative = TNative.new(self.location, builtins.NarBaseListList, { self.head:getType() })
    local newEqs, err = self.head:appendEquations(eqs, loc, localDefs, ctx, stack)
    if err ~= nil then
        return nil, err
    end
    newEqs, err = self.tail:appendEquations(newEqs, loc, localDefs, ctx, stack)
    if err ~= nil then
        return nil, err
    end
    newEqs[#newEqs + 1] = newEquation(self, self.type_, self.tail:getType())
    newEqs[#newEqs + 1] = newEquation(self, self.tail:getType(), typeNative)
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
function TyPCons:appendBytecode(ops, locations, binary, hash)
    ops, locations = self.tail:appendBytecode(ops, locations, binary, hash)
    ops, locations = self.head:appendBytecode(ops, locations, binary, hash)
    return bytecode.appendMakePattern(bytecode.PATTERN_KIND_CONS, "", 0, self.location, ops, locations, binary, hash)
end

return { TyPCons = TyPCons }
