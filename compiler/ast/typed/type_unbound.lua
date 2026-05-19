local TypedType = require("compiler.ast.typed.type").TypedType

---@class TUnbound : TypedType
---@field kind "TUnbound"
---@field location Location
---@field index integer
---@field constraint string
---@field givenName Identifier
---@field predecessor table|nil  -- normalized type with :setSuccessor(typed) method
---@field solved boolean
local TUnbound = setmetatable({}, { __index = TypedType })
TUnbound.__index = TUnbound

---Internal constructor; prefer SolvingContext:newTypeAnnotation /
---:newAnnotatedConstraint / :annotateTypeParameter.
---@param loc Location
---@param predecessor table|nil
---@param index integer
---@param constraint string
---@param givenName Identifier
---@return TUnbound
local function newTUnbound(loc, predecessor, index, constraint, givenName)
    return setmetatable({
        kind = "TUnbound",
        location = loc,
        index = index,
        constraint = constraint or "",
        givenName = givenName or "",
        predecessor = predecessor,
        solved = false,
    }, TUnbound)
end

---Public constructor (mirrors Go `typed.NewTParameter`).
---@param ctx SolvingContext
---@param loc Location
---@param predecessor table|nil
---@param name Identifier
---@return TUnbound
local function newTParameter(ctx, loc, predecessor, name)
    return ctx:annotateTypeParameter(loc, predecessor, name)
end

---@param ctx SolvingContext
---@param ubMap table<integer, integer>
---@return TUnbound
function TUnbound:makeUnique(ctx, ubMap)
    local x = ubMap[self.index]
    if x ~= nil then
        return newTUnbound(self.location, self.predecessor, x, self.constraint, self.givenName)
    end
    local ub = ctx:newAnnotatedConstraint(self, self.predecessor, self.givenName)
    ubMap[self.index] = ub.index
    return ub
end

---@param other TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TUnbound:merge(other, loc)
    error("TUnbound:merge should not be called")
end

---@param subst table<integer, TypedType>
---@return TypedType|nil t
---@return string|nil err
function TUnbound:mapTo(subst)
    if self.solved then
        return self, nil
    end
    local x = subst[self.index]
    if x ~= nil then
        if self.predecessor ~= nil then
            return self.predecessor:setSuccessor(x), nil
        end
        return x:mapTo(subst)
    end
    return nil, "failed to infer type"
end

---@param other TypedType
---@param req table<FullIdentifier, true>|nil
---@return boolean
function TUnbound:equalsTo(other, req)
    if other == nil or other.kind ~= "TUnbound" then
        return false
    end
    return self.index == other.index and self.constraint == other.constraint
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TUnbound:code(currentModule)
    if self.givenName ~= nil and self.givenName ~= "" then
        return tostring(self.givenName)
    end
    return string.format("u_%d%s", self.index, self.constraint)
end

return {
    TUnbound = TUnbound,
    newTUnbound = newTUnbound,
    newTParameter = newTParameter,
}
