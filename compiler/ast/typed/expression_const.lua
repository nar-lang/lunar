local TypedExpression = require("compiler.ast.typed.expression").TypedExpression
local newEquation = require("compiler.ast.typed.equation").newEquation
local TNative = require("compiler.ast.typed.type_native").TNative
local builtins = require("compiler.common.builtins")
local CFloat = require("compiler.ast.const").CFloat
local bytecode = require("compiler.bytecode.op")

---Mirror Go's typed.getConstType.
---@param ctx SolvingContext
---@param cv ConstValue
---@param src table
---@return TypedType
local function getConstType(ctx, cv, src)
    local k = cv.kind
    if k == "CChar" then
        return TNative.new(src.location, builtins.NarBaseCharChar, nil)
    elseif k == "CInt" then
        return ctx:newAnnotatedConstraint(src, nil, "number")
    elseif k == "CFloat" then
        return TNative.new(src.location, builtins.NarBaseMathFloat, nil)
    elseif k == "CString" then
        return TNative.new(src.location, builtins.NarBaseStringString, nil)
    elseif k == "CUnit" then
        return TNative.new(src.location, builtins.NarBaseBasicsUnit, nil)
    end
    error("getConstType: switch not exhaustive for " .. tostring(k))
end

---@param v ConstValue
---@return string
local function constCode(v)
    local k = v.kind
    if k == "CInt" then
        return string.format("%d", v.value)
    elseif k == "CFloat" then
        return string.format("%f", v.value)
    elseif k == "CString" then
        return string.format('"%s"', v.value)
    elseif k == "CChar" then
        return string.format("'%s'", v.value)
    elseif k == "CUnit" then
        return "()"
    end
    return tostring(k)
end

---@class TyConst : TypedExpression
---@field kind "TyConst"
---@field location Location
---@field type_ TypedType
---@field value ConstValue
local TyConst = setmetatable({}, { __index = TypedExpression })
TyConst.__index = TyConst

---@param ctx SolvingContext
---@param loc Location
---@param value ConstValue
---@return TyConst
function TyConst.new(ctx, loc, value)
    local e = setmetatable({
        kind = "TyConst",
        location = loc,
        type_ = nil,
        value = value,
    }, TyConst)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyConst:checkPatterns()
    return nil
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyConst:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyConst:code(currentModule)
    return constCode(self.value)
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyConst:appendEquations(eqs, loc, localDefs, ctx, stack)
    eqs[#eqs + 1] = newEquation(self, self.type_, getConstType(ctx, self.value, self))
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyConst:appendBytecode(ops, locations, binary, hash)
    local v = self.value
    if v.kind == "CInt" then
        if self.type_ ~= nil and self.type_.kind == "TNative"
            and self.type_.name == builtins.NarBaseMathFloat then
            v = CFloat.new(v.value)
        end
    end
    return v:appendBytecode(bytecode.STACK_KIND_OBJECT, self.location, ops, locations, binary, hash)
end

return {
    TyConst = TyConst,
    getConstType = getConstType,
}
