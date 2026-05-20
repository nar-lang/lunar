local TypedExpression = require("lunar.compiler.ast.typed.expression").TypedExpression
local newEquation = require("lunar.compiler.ast.typed.equation").newEquation
local TyNative = require("lunar.compiler.ast.typed.type_native").TyNative
local builtins = require("lunar.compiler.common.builtins")
local bytecode = require("lunar.compiler.bytecode.op")

---@class TyList : TypedExpression
---@field kind "TyList"
---@field location Location
---@field type_ TypedType
---@field items TypedExpression[]
---@field itemType TypedType
local TyList = setmetatable({}, { __index = TypedExpression })
TyList.__index = TyList

---@param ctx SolvingContext
---@param loc Location
---@param items TypedExpression[]
---@return TyList
function TyList.new(ctx, loc, items)
    local e = setmetatable({
        kind = "TyList",
        location = loc,
        type_ = nil,
        items = items or {},
        itemType = nil,
    }, TyList)
    e.itemType = ctx:newTypeAnnotation(e)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyList:checkPatterns()
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
function TyList:mapTypes(subst)
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
function TyList:code(currentModule)
    local parts = {}
    for _, x in ipairs(self.items) do
        parts[#parts + 1] = x:code(currentModule)
    end
    return string.format("[%s]", table.concat(parts, ", "))
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyList:appendEquations(eqs, loc, localDefs, ctx, stack)
    for _, item in ipairs(self.items) do
        eqs[#eqs + 1] = newEquation(self, self.itemType, item:getType())
    end
    local typeList = TyNative.new(self.location, builtins.NarBaseListList, { self.itemType })
    eqs[#eqs + 1] = newEquation(self, self.type_, typeList)
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
function TyList:appendBytecode(ops, locations, binary, hash)
    for _, item in ipairs(self.items) do
        ops, locations = item:appendBytecode(ops, locations, binary, hash)
    end
    return bytecode.appendMakeObject(bytecode.OBJECT_KIND_LIST, #self.items, self.location, ops, locations)
end

return { TyList = TyList }
