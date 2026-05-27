local TypedExpression = require("lunar.compiler.ast.typed.expression").TypedExpression
local newEquation = require("lunar.compiler.ast.typed.equation").newEquation
local builtins = require("lunar.compiler.common.builtins")
local bytecode = require("lunar.compiler.bytecode.op")

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
    ---@cast t -nil
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
    ---@cast defType -nil
    eqs[#eqs + 1] = newEquation(self, self.type_, defType)
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyGlobal:appendBytecode(ops, locations, binary, hash)
    local id = builtins.makeFullIdentifier(self.moduleName, self.definitionName)
    local funcIndex = hash.funcsMap[id]
    if funcIndex == nil then
        error(string.format("global definition `%s` not found at %s", id,
            (self.location and self.location:cursorString() or "<unknown>")))
    end
    return bytecode.appendLoadGlobal(funcIndex, self.location, ops, locations)
end

return { TyGlobal = TyGlobal }
