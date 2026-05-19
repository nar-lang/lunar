local TypedPattern = require("compiler.ast.typed.pattern").TypedPattern
local newEquation = require("compiler.ast.typed.equation").newEquation
local SimpleAnything = require("compiler.ast.typed.simple_pattern").SimpleAnything
local bytecode = require("compiler.bytecode.op")

---@class TyPAny : TypedPattern
---@field kind "TyPAny"
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
local TyPAny = setmetatable({}, { __index = TypedPattern })
TyPAny.__index = TyPAny

---@param ctx SolvingContext
---@param loc Location
---@param declaredType TypedType|nil
---@return TyPAny
function TyPAny.new(ctx, loc, declaredType)
    local p = setmetatable({
        kind = "TyPAny",
        location = loc,
        type_ = nil,
        declaredType = declaredType,
    }, TyPAny)
    ctx:annotatePattern(p)
    return p
end

---@return SimplePattern
function TyPAny:simplify()
    return SimpleAnything.new()
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyPAny:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyPAny:code(currentModule)
    local s = "_"
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
function TyPAny:appendEquations(eqs, loc, localDefs, ctx, stack)
    if self.declaredType ~= nil then
        eqs[#eqs + 1] = newEquation(self, self.type_, self.declaredType)
    end
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyPAny:appendBytecode(ops, locations, binary, hash)
    return bytecode.appendMakePattern(bytecode.PATTERN_KIND_ANY, "", 0, self.location, ops, locations, binary, hash)
end

return { TyPAny = TyPAny }
