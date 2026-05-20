local TypedExpression = require("lunar.compiler.ast.typed.expression").TypedExpression
local newEquation = require("lunar.compiler.ast.typed.equation").newEquation
local TyTupleType = require("lunar.compiler.ast.typed.type_tuple").TyTupleType
local bytecode = require("lunar.compiler.bytecode.op")

---@class TyTuple : TypedExpression
---@field kind "TyTuple"
---@field location Location
---@field type_ TypedType
---@field items TypedExpression[]
local TyTuple = setmetatable({}, { __index = TypedExpression })
TyTuple.__index = TyTuple

---@param ctx SolvingContext
---@param loc Location
---@param items TypedExpression[]
---@return TyTuple
function TyTuple.new(ctx, loc, items)
    local e = setmetatable({
        kind = "TyTuple",
        location = loc,
        type_ = nil,
        items = items or {},
    }, TyTuple)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyTuple:checkPatterns()
    for _, item in ipairs(self.items) do
        local err = item:checkPatterns()
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyTuple:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    ---@cast t -nil
    self.type_ = t
    for _, item in ipairs(self.items) do
        err = item:mapTypes(subst)
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyTuple:code(currentModule)
    local parts = {}
    for _, x in ipairs(self.items) do
        parts[#parts + 1] = x:code(currentModule)
    end
    return string.format("( %s )", table.concat(parts, ", "))
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyTuple:appendEquations(eqs, loc, localDefs, ctx, stack)
    ---@type TypedType[]
    local items = {}
    for i, item in ipairs(self.items) do
        local t = item:getType()
        if t == nil then
            return nil, "type cannot be inferred"
        end
        items[i] = t
    end
    eqs[#eqs + 1] = newEquation(self, self.type_, TyTupleType.new(self.location, items))
    for _, item in ipairs(self.items) do
        local newEqs, err = item:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast newEqs -nil
        eqs = newEqs
    end
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyTuple:appendBytecode(ops, locations, binary, hash)
    for _, item in ipairs(self.items) do
        ops, locations = item:appendBytecode(ops, locations, binary, hash)
    end
    return bytecode.appendMakeObject(bytecode.OBJECT_KIND_TUPLE, #self.items, self.location, ops, locations)
end

return { TyTuple = TyTuple }
