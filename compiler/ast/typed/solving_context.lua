local newTUnbound = require("lunar.compiler.ast.typed.type_unbound").newTUnbound
local equationMod = require("lunar.compiler.ast.typed.equation")
local appendUsefulEquations = equationMod.appendUsefulEquations
local builtins = require("lunar.compiler.common.builtins")

local CONSTRAINT_NONE = ""
local CONSTRAINT_NUMBER = "number"

---@class TypeGroup
---@field id integer
---@field specific TypedType|nil
---@field unbound table<integer, true>
---@field constraint string
---@field givenName Identifier
---@field givenLoc Location
local TypeGroup = {}
TypeGroup.__index = TypeGroup

local _lastGroupId = 0

---@param ub TUnbound
---@param loc Location
---@return string|nil err
function TypeGroup:absorb(ub, loc)
    if self.constraint ~= "" and ub.constraint ~= "" and self.constraint ~= ub.constraint then
        return "type constraint violation"
    end
    if ub.constraint ~= "" then
        self.constraint = ub.constraint
    end
    if (self.givenName == nil or self.givenName == "") and ub.givenName ~= "" then
        self.givenName = ub.givenName
        self.givenLoc = ub.location
    end
    if ub.location == nil or ub.location.filePath == nil or ub.location.filePath == "" then
        self.givenLoc = ub.location
    end
    self.unbound[ub.index] = true
    return nil
end

---@param type_ TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TypeGroup:specialize(type_, loc)
    if self.constraint == CONSTRAINT_NUMBER then
        local isOk = false
        if type_.kind == "TNative" then
            ---@cast type_ TyNative
            if type_.name == builtins.NarBaseMathInt or type_.name == builtins.NarBaseMathFloat then
                isOk = true
            end
        end
        if not isOk then
            return nil, string.format("numeric type cannot hold %s", type_:code(""))
        end
    end

    if self.specific == nil then
        self.specific = type_
        return nil, nil
    end
    return self.specific:merge(type_, loc)
end

---@param rg TypeGroup
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TypeGroup:merge(rg, loc)
    for ub in pairs(rg.unbound) do
        self.unbound[ub] = true
    end
    if self.constraint ~= "" and rg.constraint ~= "" and self.constraint ~= rg.constraint then
        return nil, "type constraint violation"
    end
    if rg.constraint ~= "" then
        self.constraint = rg.constraint
    end
    if rg.specific ~= nil then
        return self:specialize(rg.specific, loc)
    end
    return nil, nil
end

---@param ub TUnbound
---@return boolean
function TypeGroup:containsUnbound(ub)
    return self.unbound[ub.index] == true
end

---@param type_ TypedType|nil
---@param ub TUnbound
---@param loc Location
---@return TypeGroup|nil tg
---@return string|nil err
local function newTypeGroup(type_, ub, loc)
    _lastGroupId = _lastGroupId + 1
    local tg = setmetatable({
        id = _lastGroupId,
        specific = nil,
        unbound = {},
        constraint = CONSTRAINT_NONE,
        givenName = "",
        givenLoc = ub and ub.location or nil,
    }, TypeGroup)
    local err = tg:absorb(ub, loc)
    if err ~= nil then
        return nil, err
    end
    if type_ ~= nil then
        if type_.kind == "TUnbound" then
            ---@cast type_ TUnbound
            err = tg:absorb(type_, loc)
            if err ~= nil then
                return nil, err
            end
        else
            local _, err2 = tg:specialize(type_, loc)
            if err2 ~= nil then
                return nil, err2
            end
            ---@cast _ -nil
        end
    end
    return tg, nil
end

---@class SolvingContext
---@field annotations table[]
---@field groups TypeGroup[]
---@field numSolvedTypes integer
local SolvingContext = {}
SolvingContext.__index = SolvingContext

---@return SolvingContext
function SolvingContext.new()
    return setmetatable({
        annotations = {},
        groups = {},
        numSolvedTypes = 0,
    }, SolvingContext)
end

---@param e TypedExpression
---@return TypedExpression
function SolvingContext:annotateExpression(e)
    e:setAnnotation(self:newTypeAnnotation(e))
    return e
end

---@param p TypedPattern
---@return TypedPattern
function SolvingContext:annotatePattern(p)
    p:setAnnotation(self:newTypeAnnotation(p))
    return p
end

---@param loc Location
---@param predecessor table|nil
---@param name Identifier
---@return TUnbound
function SolvingContext:annotateTypeParameter(loc, predecessor, name)
    -- Mirror Go: ctx.newAnnotatedConstraint(&TUnbound{typeBase:&{location:loc}}, predecessor, name)
    local stmt = { kind = "TUnbound", location = loc, code = function() return "" end }
    local t = self:newAnnotatedConstraint(stmt, predecessor, name)
    self.annotations[t.index + 1] = t
    return t
end

---@param stmt table
---@return TUnbound
function SolvingContext:newTypeAnnotation(stmt)
    return self:newAnnotatedConstraint(stmt, nil, "")
end

---@param stmt table
---@param predecessor table|nil
---@param name Identifier
---@return TUnbound
function SolvingContext:newAnnotatedConstraint(stmt, predecessor, name)
    local constraint = CONSTRAINT_NONE
    if name ~= nil and name ~= "" then
        local s = tostring(name)
        if s:sub(1, #CONSTRAINT_NUMBER) == CONSTRAINT_NUMBER then
            constraint = CONSTRAINT_NUMBER
        end
    end
    local index = #self.annotations
    self.annotations[index + 1] = stmt
    local loc = (stmt.location ~= nil) and stmt.location or
        (type(stmt.Location) == "function" and stmt:Location() or nil)
    ---@cast loc Location
    local type_ = newTUnbound(loc, predecessor, index, constraint, name)
    local tg, _err = newTypeGroup(nil, type_, loc)
    self.groups[#self.groups + 1] = tg
    return type_
end

---@param loc Location
---@param name Identifier
---@return TUnbound
function SolvingContext:newSolvedType(loc, name)
    local index = #self.annotations + self.numSolvedTypes
    self.numSolvedTypes = self.numSolvedTypes + 1
    local t = newTUnbound(loc, nil, index, "", name)
    t.solved = true
    return t
end

---Substitute solving result: for every group, pick a `specific` type (or
---assign a fresh letter name a, b, c... if unsolved).
---@return table<integer, TypedType>
function SolvingContext:subst()
    local lastFreeName = 0
    ---@type table<integer, TypedType>
    local subst = {}
    for _, tg in ipairs(self.groups) do
        local type_ = tg.specific
        if type_ == nil then
            if tg.givenName == nil or tg.givenName == "" then
                local nameUsed = true
                local name
                while nameUsed do
                    nameUsed = false
                    name = string.char(string.byte("a") + lastFreeName)
                    for _, x in ipairs(self.groups) do
                        if x.givenName == name then
                            nameUsed = true
                            lastFreeName = lastFreeName + 1
                            break
                        end
                    end
                end
                tg.givenName = name
            end
            type_ = self:newSolvedType(tg.givenLoc, tg.givenName)
        end
        for ub in pairs(tg.unbound) do
            subst[ub] = type_
        end
    end
    return subst
end

---@param ub TUnbound
---@param type_ TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function SolvingContext:specialize(ub, type_, loc)
    for _, tg in ipairs(self.groups) do
        if tg:containsUnbound(ub) then
            return tg:specialize(type_, loc)
        end
    end
    return nil, string.format("cannot find annotation of `%s`", ub:code(""))
end

---@param l TUnbound
---@param r TUnbound
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function SolvingContext:merge(l, r, loc)
    ---@type Equation[]
    local additional = {}
    local i = 1
    while i <= #self.groups do
        local tga = self.groups[i]
        if tga:containsUnbound(l) then
            local j = #self.groups
            while j >= 1 do
                if j ~= i then
                    local tgb = self.groups[j]
                    if tgb:containsUnbound(r) then
                        local eqs, err = tga:merge(tgb, loc)
                        if err ~= nil then
                            return nil, err
                        end
                        ---@cast eqs -nil
                        if eqs ~= nil then
                            for _, eq in ipairs(eqs) do
                                additional[#additional + 1] = eq
                            end
                        end
                        table.remove(self.groups, j)
                        if j < i then
                            i = i - 1
                        end
                    end
                end
                j = j - 1
            end
        end
        i = i + 1
    end
    return additional, nil
end

---@param eq Equation
---@return Equation[]|nil eqs
---@return string|nil err
function SolvingContext:insert(eq)
    local left = eq.left
    local right = eq.right
    ---@type TUnbound|nil
    local lUb = nil
    if left.kind == "TUnbound" then
        ---@cast left TUnbound
        lUb = left
    end
    ---@type TUnbound|nil
    local rUb = nil
    if right.kind == "TUnbound" then
        ---@cast right TUnbound
        rUb = right
    end
    local loc = eq.stmt.location
    local eqs, err
    if lUb ~= nil and rUb ~= nil then
        eqs, err = self:merge(lUb, rUb, loc)
    elseif lUb ~= nil then
        eqs, err = self:specialize(lUb, right, loc)
    elseif rUb ~= nil then
        eqs, err = self:specialize(rUb, left, loc)
    else
        eqs, err = left:merge(right, loc)
    end
    if err ~= nil and loc ~= nil and not loc:isEmpty() then
        err = loc:cursorString() .. ": " .. err
    end
    return eqs, err
end

---@param eqs Equation[]
---@return Equation[] eqs
---@return string|nil err
function SolvingContext:insertAll(eqs)
    local i = 1
    while i <= #eqs do
        local eq = eqs[i]
        local extra, err = self:insert(eq)
        if extra ~= nil then
            eqs = appendUsefulEquations(eqs, extra)
        end
        if err ~= nil then
            return eqs, err
        end
        i = i + 1
    end
    return eqs, nil
end

return {
    SolvingContext = SolvingContext,
    TypeGroup = TypeGroup,
    newTypeGroup = newTypeGroup,
}
