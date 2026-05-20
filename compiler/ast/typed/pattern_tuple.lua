local TypedPattern = require("compiler.ast.typed.pattern").TypedPattern
local newEquation = require("compiler.ast.typed.equation").newEquation
local TyTupleType = require("compiler.ast.typed.type_tuple").TyTupleType
local TyData = require("compiler.ast.typed.type_data").TyData
local TyDataOption = require("compiler.ast.typed.type_data").TyDataOption
local SimpleConstructor = require("compiler.ast.typed.simple_pattern").SimpleConstructor
local bytecode = require("compiler.bytecode.op")

---@class TyPTuple : TypedPattern
---@field kind "TyPTuple"
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
---@field items TypedPattern[]
local TyPTuple = setmetatable({}, { __index = TypedPattern })
TyPTuple.__index = TyPTuple

---@param ctx SolvingContext
---@param loc Location
---@param declaredType TypedType|nil
---@param items TypedPattern[]
---@return TyPTuple|nil
---@return string|nil err
function TyPTuple.new(ctx, loc, declaredType, items)
    if #items > 255 then
        return nil, "too many items in tuple (max 255)"
    end
    local p = setmetatable({
        kind = "TyPTuple",
        location = loc,
        type_ = nil,
        declaredType = declaredType,
        items = items or {},
    }, TyPTuple)
    ctx:annotatePattern(p)
    return p, nil
end

---@return SimpleConstructor
function TyPTuple:simplify()
    ---@type SimplePattern[]
    local args = {}
    for i, x in ipairs(self.items) do
        args[i] = x:simplify()
    end
    ---@type TypedType[]
    local values = {}
    for i, x in ipairs(self.items) do
        values[i] = x:getType()
    end
    local union = TyData.new(
        self.location,
        string.format("!!%d", #self.items),
        nil,
        { TyDataOption.new("Only", values) })
    return SimpleConstructor.new(union, "Only", args)
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyPTuple:mapTypes(subst)
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
function TyPTuple:code(currentModule)
    local parts = {}
    for _, x in ipairs(self.items) do
        parts[#parts + 1] = x:code(currentModule)
    end
    return "(" .. table.concat(parts, ", ") .. ")"
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyPTuple:appendEquations(eqs, loc, localDefs, ctx, stack)
    ---@type TypedType[]
    local items = {}
    for i, e in ipairs(self.items) do
        local t = e:getType()
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
function TyPTuple:appendBytecode(ops, locations, binary, hash)
    for _, item in ipairs(self.items) do
        ops, locations = item:appendBytecode(ops, locations, binary, hash)
    end
    return bytecode.appendMakePattern(bytecode.PATTERN_KIND_TUPLE, "", #self.items, self.location, ops, locations, binary, hash)
end

return { TyPTuple = TyPTuple }
