local TypedPattern = require("lunar.compiler.ast.typed.pattern").TypedPattern
local newEquation = require("lunar.compiler.ast.typed.equation").newEquation
local SimpleLiteral = require("lunar.compiler.ast.typed.simple_pattern").SimpleLiteral
local SimpleConstructor = require("lunar.compiler.ast.typed.simple_pattern").SimpleConstructor
local TyData = require("lunar.compiler.ast.typed.type_data").TyData
local TyDataOption = require("lunar.compiler.ast.typed.type_data").TyDataOption
local bytecode = require("lunar.compiler.bytecode.op")

---@class TyPConst : TypedPattern
---@field kind "TyPConst"
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
---@field value ConstValue
local TyPConst = setmetatable({}, { __index = TypedPattern })
TyPConst.__index = TyPConst

---@param ctx SolvingContext
---@param loc Location
---@param declaredType TypedType|nil
---@param value ConstValue
---@return TyPConst
function TyPConst.new(ctx, loc, declaredType, value)
    local p = setmetatable({
        kind = "TyPConst",
        location = loc,
        type_ = nil,
        declaredType = declaredType,
        value = value,
    }, TyPConst)
    ctx:annotatePattern(p)
    return p
end

---@return SimplePattern
function TyPConst:simplify()
    if self.value.kind == "CUnit" then
        local union = TyData.new(self.location, "!!Unit", nil, { TyDataOption.new("Only", nil) })
        return SimpleConstructor.new(union, "Only", nil)
    end
    return SimpleLiteral.new(self.value)
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyPConst:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    ---@cast t -nil
    self.type_ = t
    return nil
end

---@param v ConstValue
---@return string
local function constCode(v)
    local k = v.kind
    if k == "CInt" then
        ---@cast v CInt
        return string.format("%d", v.value)
    elseif k == "CFloat" then
        ---@cast v CFloat
        return string.format("%f", v.value)
    elseif k == "CString" then
        ---@cast v CString
        return string.format('"%s"', v.value)
    elseif k == "CChar" then
        ---@cast v CChar
        return string.format("'%s'", v.value)
    elseif k == "CUnit" then
        return "()"
    end
    return tostring(k)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyPConst:code(currentModule)
    local s = constCode(self.value)
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
function TyPConst:appendEquations(eqs, loc, localDefs, ctx, stack)
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
function TyPConst:appendBytecode(ops, locations, binary, hash)
    ops, locations = self.value:appendBytecode(bytecode.STACK_KIND_PATTERN, self.location, ops, locations, binary, hash)
    return bytecode.appendMakePattern(bytecode.PATTERN_KIND_CONST, "", 0, self.location, ops, locations, binary, hash)
end

return { TyPConst = TyPConst }
