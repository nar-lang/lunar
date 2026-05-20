local TypedPattern = require("compiler.ast.typed.pattern").TypedPattern
local newEquation = require("compiler.ast.typed.equation").newEquation
local SimpleAnything = require("compiler.ast.typed.simple_pattern").SimpleAnything
local bytecode = require("compiler.bytecode.op")

---@class TyPNamed : TypedPattern
---@field kind "TyPNamed"
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
---@field name Identifier
local TyPNamed = setmetatable({}, { __index = TypedPattern })
TyPNamed.__index = TyPNamed

---@param ctx SolvingContext
---@param loc Location
---@param declaredType TypedType|nil
---@param name Identifier
---@return TyPNamed
function TyPNamed.new(ctx, loc, declaredType, name)
    local p = setmetatable({
        kind = "TyPNamed",
        location = loc,
        type_ = nil,
        declaredType = declaredType,
        name = name,
    }, TyPNamed)
    ctx:annotatePattern(p)
    return p
end

---@return SimpleAnything
function TyPNamed:simplify()
    return SimpleAnything.new()
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyPNamed:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    ---@cast t -nil
    self.type_ = t
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyPNamed:code(currentModule)
    local s = tostring(self.name)
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
function TyPNamed:appendEquations(eqs, loc, localDefs, ctx, stack)
    localDefs[self.name] = self.type_
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
function TyPNamed:appendBytecode(ops, locations, binary, hash)
    return bytecode.appendMakePattern(bytecode.PATTERN_KIND_NAMED, self.name, 0, self.location, ops, locations, binary, hash)
end

return { TyPNamed = TyPNamed }
