local TypedStatement = require("lunar.compiler.ast.typed.defines").TypedStatement

---@class TypedPattern : TypedStatement
---@field kind string
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
local TypedPattern = setmetatable({}, { __index = TypedStatement })
TypedPattern.__index = TypedPattern

---@return TypedType
function TypedPattern:getType()
    return self.type_
end

---@return TypedType|nil
function TypedPattern:getDeclaredType()
    return self.declaredType
end

---@param annotation TUnbound
function TypedPattern:setAnnotation(annotation)
    self.type_ = annotation
end

---@return SimplePattern
function TypedPattern:simplify()
    error("abstract method 'simplify' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TypedPattern:appendEquations(eqs, loc, localDefs, ctx, stack)
    error("abstract method 'appendEquations' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TypedPattern:mapTypes(subst)
    error("abstract method 'mapTypes' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TypedPattern:code(currentModule)
    error("abstract method 'code' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TypedPattern:appendBytecode(ops, locations, binary, hash)
    error("abstract method 'appendBytecode' not implemented for kind=" .. tostring(self.kind), 2)
end

return { TypedPattern = TypedPattern }
