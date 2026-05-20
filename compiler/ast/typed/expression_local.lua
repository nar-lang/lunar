local TypedExpression = require("lunar.compiler.ast.typed.expression").TypedExpression
local newEquation = require("lunar.compiler.ast.typed.equation").newEquation
local bytecode = require("lunar.compiler.bytecode.op")

---@class TyLocal : TypedExpression
---@field kind "TyLocal"
---@field location Location
---@field type_ TypedType
---@field name Identifier
---@field target TypedPattern|nil
local TyLocal = setmetatable({}, { __index = TypedExpression })
TyLocal.__index = TyLocal

---@param ctx SolvingContext
---@param loc Location
---@param name Identifier
---@param target TypedPattern|nil
---@return TyLocal
function TyLocal.new(ctx, loc, name, target)
    local e = setmetatable({
        kind = "TyLocal",
        location = loc,
        type_ = nil,
        name = name,
        target = target,
    }, TyLocal)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyLocal:checkPatterns()
    return nil
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyLocal:mapTypes(subst)
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
function TyLocal:code(currentModule)
    return tostring(self.name)
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyLocal:appendEquations(eqs, loc, localDefs, ctx, stack)
    if self.target ~= nil then
        eqs[#eqs + 1] = newEquation(self, self.type_, self.target:getType())
    else
        return nil, string.format("local `%s` not found", self.name)
    end
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyLocal:appendBytecode(ops, locations, binary, hash)
    return bytecode.appendLoadLocal(self.name, self.location, ops, locations, binary, hash)
end

return { TyLocal = TyLocal }
