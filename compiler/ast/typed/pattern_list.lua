local TypedPattern = require("compiler.ast.typed.pattern").TypedPattern
local newEquation = require("compiler.ast.typed.equation").newEquation
local TNative = require("compiler.ast.typed.type_native").TNative
local TData = require("compiler.ast.typed.type_data").TData
local DataOption = require("compiler.ast.typed.type_data").DataOption
local SimpleConstructor = require("compiler.ast.typed.simple_pattern").SimpleConstructor
local builtins = require("compiler.common.builtins")
local bytecode = require("compiler.bytecode.op")

---@class TyPList : TypedPattern
---@field kind "TyPList"
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
---@field items TypedPattern[]
---@field itemType TypedType
---@field ctx SolvingContext
local TyPList = setmetatable({}, { __index = TypedPattern })
TyPList.__index = TyPList

---@param ctx SolvingContext
---@param loc Location
---@param declaredType TypedType|nil
---@param items TypedPattern[]
---@return TyPList
function TyPList.new(ctx, loc, declaredType, items)
    local p = setmetatable({
        kind = "TyPList",
        location = loc,
        type_ = nil,
        declaredType = declaredType,
        items = items or {},
        itemType = nil,
        ctx = ctx,
    }, TyPList)
    p.itemType = ctx:newTypeAnnotation(p)
    ctx:annotatePattern(p)
    return p
end

---@return SimpleConstructor
function TyPList:simplify()
    local ctor = "Nil"
    local nested = nil
    if #self.items > 0 then
        local rest = {}
        for i = 2, #self.items do
            rest[#rest + 1] = self.items[i]
        end
        local tail = TyPList.new(self.ctx, self.location, nil, rest)
        local item = tail:simplify()
        ctor = "Cons"
        nested = { item }
    end
    local a = self.ctx:newTypeAnnotation(self)
    local union = TData.new(self.location, "!!list", nil, {
        DataOption.new("Nil", nil),
        DataOption.new("Cons", { a, TNative.new(self.location, builtins.NarBaseListList, { a }) }),
    })
    return SimpleConstructor.new(union, ctor, nested)
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyPList:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
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
function TyPList:code(currentModule)
    local parts = {}
    for _, x in ipairs(self.items) do
        parts[#parts + 1] = x:code(currentModule)
    end
    local s = string.format("[%s]", table.concat(parts, ", "))
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
function TyPList:appendEquations(eqs, loc, localDefs, ctx, stack)
    for _, item in ipairs(self.items) do
        eqs[#eqs + 1] = newEquation(item, self.itemType, item:getType())
    end
    local typeNative = TNative.new(self.location, builtins.NarBaseListList, { self.itemType })
    eqs[#eqs + 1] = newEquation(self, self.type_, typeNative)
    for _, item in ipairs(self.items) do
        local newEqs, err = item:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
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
function TyPList:appendBytecode(ops, locations, binary, hash)
    for _, item in ipairs(self.items) do
        ops, locations = item:appendBytecode(ops, locations, binary, hash)
    end
    return bytecode.appendMakePatternLong(bytecode.PATTERN_KIND_LIST, #self.items, self.location, ops, locations, binary)
end

return { TyPList = TyPList }
