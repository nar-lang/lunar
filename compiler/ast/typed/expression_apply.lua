local TypedExpression = require("compiler.ast.typed.expression").TypedExpression
local newEquation = require("compiler.ast.typed.equation").newEquation
local TFunc = require("compiler.ast.typed.type_func").TFunc
local bytecode = require("compiler.bytecode.op")

---@class TyApply : TypedExpression
---@field kind "TyApply"
---@field location Location
---@field type_ TypedType
---@field func TypedExpression
---@field args TypedExpression[]
local TyApply = setmetatable({}, { __index = TypedExpression })
TyApply.__index = TyApply

---@param ctx SolvingContext
---@param loc Location
---@param func TypedExpression
---@param args TypedExpression[]
---@return TyApply|nil
---@return string|nil err
function TyApply.new(ctx, loc, func, args)
    if #args > 255 then
        return nil, "too many arguments (max 255)"
    end
    local e = setmetatable({
        kind = "TyApply",
        location = loc,
        type_ = nil,
        func = func,
        args = args or {},
    }, TyApply)
    ctx:annotateExpression(e)
    return e, nil
end

---@return string|nil err
function TyApply:checkPatterns()
    local err = self.func:checkPatterns()
    if err ~= nil then
        return err
    end
    for _, arg in ipairs(self.args) do
        err = arg:checkPatterns()
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyApply:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    for _, arg in ipairs(self.args) do
        err = arg:mapTypes(subst)
        if err ~= nil then
            return err
        end
    end
    return self.func:mapTypes(subst)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyApply:code(currentModule)
    local parts = {}
    for _, a in ipairs(self.args) do
        parts[#parts + 1] = a:code(currentModule)
    end
    return string.format("%s(%s)", self.func:code(currentModule), table.concat(parts, ", "))
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyApply:appendEquations(eqs, loc, localDefs, ctx, stack)
    ---@type TypedType[]
    local paramTypes = {}
    for i, a in ipairs(self.args) do
        paramTypes[i] = a:getType()
    end
    local funcType = TFunc.new(self.location, paramTypes, self.type_)
    eqs[#eqs + 1] = newEquation(self, self.func:getType(), funcType)
    local newEqs, err = self.func:appendEquations(eqs, loc, localDefs, ctx, stack)
    if err ~= nil then
        return nil, err
    end
    for _, arg in ipairs(self.args) do
        newEqs, err = arg:appendEquations(newEqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
    end
    return newEqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyApply:appendBytecode(ops, locations, binary, hash)
    for _, arg in ipairs(self.args) do
        ops, locations = arg:appendBytecode(ops, locations, binary, hash)
    end
    ops, locations = self.func:appendBytecode(ops, locations, binary, hash)
    return bytecode.appendApply(#self.args, self.location, ops, locations)
end

return { TyApply = TyApply }
