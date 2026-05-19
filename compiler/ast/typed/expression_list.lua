local TypedExpression = require("compiler.ast.typed.expression").TypedExpression
local newEquation = require("compiler.ast.typed.equation").newEquation
local TNative = require("compiler.ast.typed.type_native").TNative
local builtins = require("compiler.common.builtins")

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
    local typeList = TNative.new(self.location, builtins.NarBaseListList, { self.itemType })
    eqs[#eqs + 1] = newEquation(self, self.type_, typeList)
    for _, item in ipairs(self.items) do
        local newEqs, err = item:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
        eqs = newEqs
    end
    return eqs, nil
end

return { TyList = TyList }
