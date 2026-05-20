local TypedType = require("lunar.compiler.ast.typed.type").TypedType
local newEquationBestLoc = require("lunar.compiler.ast.typed.equation").newEquationBestLoc

---@class TyTupleType : TypedType
---@field kind "TTuple"
---@field location Location
---@field items TypedType[]
local TyTupleType = setmetatable({}, { __index = TypedType })
TyTupleType.__index = TyTupleType

---@param loc Location
---@param items TypedType[]|nil
---@return TyTupleType
function TyTupleType.new(loc, items)
    return setmetatable({
        kind = "TTuple",
        location = loc,
        items = items or {},
    }, TyTupleType)
end

---@param ctx SolvingContext
---@param ubMap table<integer, integer>
---@return TyTupleType
function TyTupleType:makeUnique(ctx, ubMap)
    ---@type TypedType[]
    local items = {}
    for i, x in ipairs(self.items) do
        items[i] = x:makeUnique(ctx, ubMap)
    end
    return TyTupleType.new(self.location, items)
end

---@param other TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TyTupleType:merge(other, loc)
    if other ~= nil and other.kind == "TTuple" then
        ---@cast other TyTupleType
        if #self.items == #other.items then
            ---@type Equation[]
            local eqs = {}
            for i, p in ipairs(self.items) do
                eqs[#eqs + 1] = newEquationBestLoc(p, other.items[i], loc)
            end
            return eqs, nil
        end
    end
    return nil, string.format("cannot match %s and %s", other:code(""), self:code(""))
end

---@param subst table<integer, TypedType>
---@return TypedType|nil t
---@return string|nil err
function TyTupleType:mapTo(subst)
    for i, p in ipairs(self.items) do
        local x, err = p:mapTo(subst)
        if err ~= nil then
            return nil, err
        end
        ---@cast x -nil
        self.items[i] = x
    end
    return self, nil
end

---@param other TypedType
---@param req table<FullIdentifier, true>|nil
---@return boolean
function TyTupleType:equalsTo(other, req)
    if other == nil or other.kind ~= "TTuple" then
        return false
    end
    ---@cast other TyTupleType
    if #self.items ~= #other.items then
        return false
    end
    for i, p in ipairs(self.items) do
        if not p:equalsTo(other.items[i], req) then
            return false
        end
    end
    return true
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyTupleType:code(currentModule)
    local parts = {}
    for _, x in ipairs(self.items) do
        parts[#parts + 1] = x:code("")
    end
    return string.format("( %s )", table.concat(parts, ", "))
end

return { TyTupleType = TyTupleType }
