local TypedStatement = require("compiler.ast.typed.defines").TypedStatement

---@class TypedExpression : TypedStatement
---@field kind string
---@field location Location
---@field type_ TypedType
local TypedExpression = setmetatable({}, { __index = TypedStatement })
TypedExpression.__index = TypedExpression

---@return TypedType
function TypedExpression:getType()
    return self.type_
end

---@param annotation TUnbound
function TypedExpression:setAnnotation(annotation)
    self.type_ = annotation
end

---Generate type equations for this expression. Returns extended `eqs` or
---`(nil, err)`.
---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TypedExpression:appendEquations(eqs, loc, localDefs, ctx, stack)
    error("abstract method 'appendEquations' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TypedExpression:mapTypes(subst)
    error("abstract method 'mapTypes' not implemented for kind=" .. tostring(self.kind), 2)
end

---@return string|nil err
function TypedExpression:checkPatterns()
    error("abstract method 'checkPatterns' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TypedExpression:code(currentModule)
    error("abstract method 'code' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TypedExpression:appendBytecode(ops, locations, binary, hash)
    error("abstract method 'appendBytecode' not implemented for kind=" .. tostring(self.kind), 2)
end

return { TypedExpression = TypedExpression }
