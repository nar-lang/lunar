local TypedStatement = require("compiler.ast.typed.defines").TypedStatement
local SolvingContext = require("compiler.ast.typed.solving_context").SolvingContext
local equationMod = require("compiler.ast.typed.equation")
local newEquation = equationMod.newEquation
local appendUsefulEquations = equationMod.appendUsefulEquations
local TFunc = require("compiler.ast.typed.type_func").TFunc

---@class TypedDefinition : TypedStatement
---@field kind "TypedDefinition"
---@field id integer
---@field name Identifier
---@field nameLocation Location
---@field location Location
---@field params TypedPattern[]
---@field body TypedExpression|nil
---@field declaredType TypedType|nil
---@field type_ TypedType
---@field hidden boolean
---@field ctx SolvingContext
---@field typed boolean
local TypedDefinition = setmetatable({}, { __index = TypedStatement })
TypedDefinition.__index = TypedDefinition

---@param location Location
---@param id integer
---@param hidden boolean
---@param name Identifier
---@param nameLocation Location
---@return TypedDefinition
function TypedDefinition.new(location, id, hidden, name, nameLocation)
    local def = setmetatable({
        kind = "TypedDefinition",
        id = id,
        name = name,
        location = location,
        nameLocation = nameLocation,
        params = {},
        body = nil,
        declaredType = nil,
        type_ = nil,
        hidden = hidden,
        ctx = SolvingContext.new(),
        typed = false,
    }, TypedDefinition)
    def.type_ = def.ctx:newTypeAnnotation(def)
    return def
end

---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return TypedType|nil
---@return string|nil err
function TypedDefinition:uniqueType(ctx, stack)
    local t = self.declaredType
    if t == nil and self.typed then
        t = self.type_
    end
    if t == nil then
        for _, sd in ipairs(stack) do
            if sd.id == self.id then
                return sd.type_, nil
            end
        end
        local err = self:solveTypes(stack)
        if err ~= nil then
            return nil, err
        end
        t = self.type_
    end
    return t:makeUnique(ctx, {}), nil
end

---@param stack TypedDefinition[]
---@return string|nil err
function TypedDefinition:solveTypes(stack)
    stack = stack or {}
    stack[#stack + 1] = self
    local eqs, err = self:appendEquations({}, nil, {}, self.ctx, stack)
    if err ~= nil then
        return err
    end
    eqs = appendUsefulEquations({}, eqs)
    eqs, err = self.ctx:insertAll(eqs)
    if err ~= nil then
        return err
    end
    local subst = self.ctx:subst()
    err = self:mapTypes(subst)
    if err ~= nil then
        return err
    end
    stack[#stack] = nil
    return nil
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TypedDefinition:mapTypes(subst)
    for _, p in ipairs(self.params) do
        local err = p:mapTypes(subst)
        if err ~= nil then
            return err
        end
    end
    local t, err = self.type_:mapTo(subst)
    self.typed = true
    if err ~= nil then
        return err
    end
    self.type_ = t
    if self.body == nil then
        return nil
    end
    return self.body:mapTypes(subst)
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TypedDefinition:appendEquations(eqs, loc, localDefs, ctx, stack)
    if self.body ~= nil then
        ---@type TypedType
        local defType = self.body:getType()
        if #self.params > 0 then
            ---@type TypedType[]
            local paramTypes = {}
            for i, p in ipairs(self.params) do
                paramTypes[i] = p:getType()
            end
            defType = TFunc.new(self.location, paramTypes, defType)
        end
        eqs[#eqs + 1] = newEquation(defType, self.type_, defType)
        if self.declaredType ~= nil then
            eqs[#eqs + 1] = newEquation(defType, self.declaredType, defType)
        end
    end
    for _, p in ipairs(self.params) do
        local newEqs, err = p:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
        eqs = newEqs
    end
    if self.body ~= nil then
        local newEqs, err = self.body:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
        eqs = newEqs
    end
    return eqs, nil
end

---@return string|nil err
function TypedDefinition:checkPatterns()
    local utils = require("compiler.ast.typed.utils")
    for _, pattern in ipairs(self.params) do
        local err = utils.checkPattern(pattern)
        if err ~= nil then
            return err
        end
    end
    if self.body ~= nil then
        return self.body:checkPatterns()
    end
    return nil
end

---@param body TypedExpression
function TypedDefinition:setExpression(body)
    self.body = body
end

---@param params TypedPattern[]
function TypedDefinition:setParams(params)
    self.params = params
end

---@param declaredType TypedType|nil
function TypedDefinition:setDeclaredType(declaredType)
    self.declaredType = declaredType
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TypedDefinition:code(currentModule)
    local parts = {}
    for _, p in ipairs(self.params) do
        parts[#parts + 1] = p:code(currentModule)
    end
    local params = table.concat(parts, ", ")
    if params ~= "" then
        params = "(" .. params .. ")"
    end
    local typeString = ""
    if self.declaredType ~= nil then
        if self.declaredType.kind == "TFunc" then
            typeString = ": " .. self.declaredType.return_:code(currentModule)
        else
            typeString = ": " .. self.declaredType:code(currentModule)
        end
    end
    if self.body == nil then
        return string.format("def %s%s%s", self.name, params, typeString)
    end
    return string.format("def %s%s%s = %s", self.name, params, typeString,
        self.body:code(currentModule))
end

return { TypedDefinition = TypedDefinition }
