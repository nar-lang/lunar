local TypedType = require("lunar.compiler.ast.typed.type").TypedType
local newEquationBestLoc = require("lunar.compiler.ast.typed.equation").newEquationBestLoc

---@class TyFunc : TypedType
---@field kind "TFunc"
---@field location Location
---@field params TypedType[]
---@field return_ TypedType
local TyFunc = setmetatable({}, { __index = TypedType })
TyFunc.__index = TyFunc

---@param loc Location
---@param params TypedType[]|nil
---@param ret TypedType
---@return TyFunc
function TyFunc.new(loc, params, ret)
    return setmetatable({
        kind = "TFunc",
        location = loc,
        params = params or {},
        return_ = ret,
    }, TyFunc)
end

---@param ctx SolvingContext
---@param ubMap table<integer, integer>
---@return TyFunc
function TyFunc:makeUnique(ctx, ubMap)
    ---@type TypedType[]
    local ps = {}
    for i, p in ipairs(self.params) do
        ps[i] = p:makeUnique(ctx, ubMap)
    end
    return TyFunc.new(self.location, ps, self.return_:makeUnique(ctx, ubMap))
end

---Pad/balance the function shape (Curry by reshape).
---@param sz integer
---@return TyFunc
function TyFunc:balance(sz)
    if #self.params == sz then
        return self
    end
    ---@type TypedType[]
    local head = {}
    for i = 1, sz do
        head[i] = self.params[i]
    end
    ---@type TypedType[]
    local tail = {}
    for i = sz + 1, #self.params do
        tail[i - sz] = self.params[i]
    end
    return TyFunc.new(self.location, head, TyFunc.new(self.location, tail, self.return_))
end

---@param other TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TyFunc:merge(other, loc)
    if other == nil or other.kind ~= "TFunc" then
        local otherCode = other ~= nil and other:code("") or "nil"
        return nil, string.format("cannot match %s and %s", otherCode, self:code(""))
    end
    ---@cast other TyFunc
    local t1 = self
    local t2 = other
    if #t1.params < #t2.params then
        t2 = t2:balance(#t1.params)
    elseif #t1.params > #t2.params then
        t1 = t1:balance(#t2.params)
    end
    ---@type Equation[]
    local eqs = {}
    for i, p in ipairs(t1.params) do
        eqs[#eqs + 1] = newEquationBestLoc(p, t2.params[i], loc)
    end
    eqs[#eqs + 1] = newEquationBestLoc(t1.return_, t2.return_, loc)
    return eqs, nil
end

---@param subst table<integer, TypedType>
---@return TypedType|nil t
---@return string|nil err
function TyFunc:mapTo(subst)
    for i, p in ipairs(self.params) do
        local x, err = p:mapTo(subst)
        if err ~= nil then
            return nil, err
        end
        ---@cast x -nil
        self.params[i] = x
    end
    local r, err = self.return_:mapTo(subst)
    if err ~= nil then
        return nil, err
    end
    ---@cast r -nil
    self.return_ = r
    return self, nil
end

---@param other TypedType
---@param req table<FullIdentifier, true>|nil
---@return boolean
function TyFunc:equalsTo(other, req)
    if other == nil or other.kind ~= "TFunc" then
        return false
    end
    ---@cast other TyFunc
    if #self.params ~= #other.params then
        return false
    end
    for i, p in ipairs(self.params) do
        if not p:equalsTo(other.params[i], req) then
            return false
        end
    end
    return self.return_:equalsTo(other.return_, req)
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyFunc:code(currentModule)
    local parts = {}
    for _, p in ipairs(self.params) do
        parts[#parts + 1] = p:code("")
    end
    return string.format("(%s) -> %s", table.concat(parts, ", "), self.return_:code(""))
end

return { TyFunc = TyFunc }
