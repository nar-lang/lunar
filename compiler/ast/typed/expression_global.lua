local TypedExpression = require("compiler.ast.typed.expression").TypedExpression
local newEquation = require("compiler.ast.typed.equation").newEquation
local builtins = require("compiler.common.builtins")

---@class TyGlobal : TypedExpression
---@field kind "TyGlobal"
---@field location Location
---@field type_ TypedType
---@field moduleName QualifiedIdentifier
---@field definitionName Identifier
---@field definition TypedDefinition|nil
local TyGlobal = setmetatable({}, { __index = TypedExpression })
TyGlobal.__index = TyGlobal

---@param ctx SolvingContext
---@param loc Location
---@param moduleName QualifiedIdentifier
---@param definitionName Identifier
---@param targetDef TypedDefinition|nil
---@return TyGlobal
function TyGlobal.new(ctx, loc, moduleName, definitionName, targetDef)
    local e = setmetatable({
        kind = "TyGlobal",
        location = loc,
        type_ = nil,
        moduleName = moduleName,
        definitionName = definitionName,
        definition = targetDef,
    }, TyGlobal)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyGlobal:checkPatterns()
    return nil
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyGlobal:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyGlobal:code(currentModule)
    local name = tostring(self.definitionName)
    if currentModule ~= self.moduleName then
        name = builtins.makeFullIdentifier(self.moduleName, self.definitionName)
    end
    return name
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyGlobal:appendEquations(eqs, loc, localDefs, ctx, stack)
    if self.definition == nil then
        return nil, string.format("definition `%s` not found", self.definitionName)
    end
    local defType, err = self.definition:uniqueType(ctx, stack)
    if err ~= nil then
        return nil, err
    end
    eqs[#eqs + 1] = newEquation(self, self.type_, defType)
    return eqs, nil
end

return { TyGlobal = TyGlobal }
