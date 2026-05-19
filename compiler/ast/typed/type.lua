local TypedStatement = require("compiler.ast.typed.defines").TypedStatement

---@class TypedType : TypedStatement
---@field kind string
---@field location Location
local TypedType = setmetatable({}, { __index = TypedStatement })
TypedType.__index = TypedType

---Merge this type with another; returns extra equations on success.
---@param other TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TypedType:merge(other, loc)
    error("abstract method 'merge' not implemented for kind=" .. tostring(self.kind), 2)
end

---Map this type through a substitution map (uint64 -> TypedType).
---Returns the new (or same) type, or (nil, err).
---@param subst table<integer, TypedType>
---@return TypedType|nil t
---@return string|nil err
function TypedType:mapTo(subst)
    error("abstract method 'mapTo' not implemented for kind=" .. tostring(self.kind), 2)
end

---Clone with fresh unbound type variables.
---@param ctx SolvingContext
---@param ubMap table<integer, integer>
---@return TypedType
function TypedType:makeUnique(ctx, ubMap)
    error("abstract method 'makeUnique' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param other TypedType
---@param req table<FullIdentifier, true>|nil
---@return boolean
function TypedType:equalsTo(other, req)
    error("abstract method 'equalsTo' not implemented for kind=" .. tostring(self.kind), 2)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TypedType:code(currentModule)
    error("abstract method 'code' not implemented for kind=" .. tostring(self.kind), 2)
end

return { TypedType = TypedType }
