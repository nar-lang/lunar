local TypedExpression = require("lunar.compiler.ast.typed.expression").TypedExpression
local newEquation = require("lunar.compiler.ast.typed.equation").newEquation
local TyRecordType = require("lunar.compiler.ast.typed.type_record").TyRecordType
local bytecode = require("lunar.compiler.bytecode.op")

---@class TyAccess : TypedExpression
---@field kind "TyAccess"
---@field location Location
---@field type_ TypedType
---@field fieldName Identifier
---@field record TypedExpression
local TyAccess = setmetatable({}, { __index = TypedExpression })
TyAccess.__index = TyAccess

---@param ctx SolvingContext
---@param loc Location
---@param fieldName Identifier
---@param record TypedExpression
---@return TyAccess
function TyAccess.new(ctx, loc, fieldName, record)
    local e = setmetatable({
        kind = "TyAccess",
        location = loc,
        type_ = nil,
        fieldName = fieldName,
        record = record,
    }, TyAccess)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyAccess:checkPatterns()
    return self.record:checkPatterns()
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyAccess:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    ---@cast t -nil
    self.type_ = t
    return self.record:mapTypes(subst)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyAccess:code(currentModule)
    return string.format("%s.%s", self.record:code(currentModule), self.fieldName)
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyAccess:appendEquations(eqs, loc, localDefs, ctx, stack)
    local fields = { [self.fieldName] = self.type_ }
    eqs[#eqs + 1] = newEquation(self, TyRecordType.new(self.location, fields, true), self.record:getType())
    local newEqs, err = self.record:appendEquations(eqs, loc, localDefs, ctx, stack)
    if err ~= nil then
        return nil, err
    end
    ---@cast newEqs -nil
    return newEqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyAccess:appendBytecode(ops, locations, binary, hash)
    ops, locations = self.record:appendBytecode(ops, locations, binary, hash)
    return bytecode.appendAccess(self.fieldName, self.location, ops, locations, binary, hash)
end

return { TyAccess = TyAccess }
