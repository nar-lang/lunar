local TypedPattern = require("compiler.ast.typed.pattern").TypedPattern
local newEquation = require("compiler.ast.typed.equation").newEquation
local TyFunc = require("compiler.ast.typed.type_func").TyFunc
local SimpleConstructor = require("compiler.ast.typed.simple_pattern").SimpleConstructor
local builtins = require("compiler.common.builtins")
local bytecode = require("compiler.bytecode.op")

---@class TyPOption : TypedPattern
---@field kind "TyPOption"
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
---@field definition TypedDefinition|nil
---@field args TypedPattern[]
local TyPOption = setmetatable({}, { __index = TypedPattern })
TyPOption.__index = TyPOption

---@param ctx SolvingContext
---@param loc Location
---@param declaredType TypedType|nil
---@param definition TypedDefinition|nil
---@param args TypedPattern[]
---@return TyPOption|nil
---@return string|nil err
function TyPOption.new(ctx, loc, declaredType, definition, args)
    if #args > 255 then
        return nil, "too many arguments (max 255)"
    end
    local p = setmetatable({
        kind = "TyPOption",
        location = loc,
        type_ = nil,
        declaredType = declaredType,
        definition = definition,
        args = args or {},
    }, TyPOption)
    ctx:annotatePattern(p)
    return p, nil
end

---Extract data option identifier from the definition's constructor body.
---@return string
function TyPOption:name()
    local body = self.definition and self.definition.body
    if body == nil or body.kind ~= "TyConstructor" then
        error("Data option pattern should have a constructor definition.")
    end
    ---@cast body TyConstructor
    return builtins.makeDataOptionIdentifier(body.dataName, body.optionName)
end

---@return SimpleConstructor
function TyPOption:simplify()
    ---@type SimplePattern[]
    local args = {}
    for i, x in ipairs(self.args) do
        args[i] = x:simplify()
    end
    local t = self.type_
    if t ~= nil and t.kind == "TData" then
        ---@cast t TyData
        return SimpleConstructor.new(t, self:name(), args)
    end
    error("Data option pattern should have a data type.")
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyPOption:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    ---@cast t -nil
    self.type_ = t
    for _, arg in ipairs(self.args) do
        err = arg:mapTypes(subst)
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyPOption:code(currentModule)
    local s = self:name()
    if #self.args > 0 then
        local parts = {}
        for _, x in ipairs(self.args) do
            parts[#parts + 1] = x:code(currentModule)
        end
        s = s .. "(" .. table.concat(parts, ", ") .. ")"
    end
    if self.declaredType ~= nil then
        s = s .. ": " .. self.declaredType:code(currentModule)
    end
    return s
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyPOption:appendEquations(eqs, loc, localDefs, ctx, stack)
    if self.definition == nil then
        return nil, "definition not found"
    end
    local defType, err = self.definition:uniqueType(ctx, stack)
    if err ~= nil then
        return nil, err
    end
    ---@cast defType -nil
    if #self.args == 0 then
        eqs[#eqs + 1] = newEquation(self, self.type_, defType)
    else
        ---@type TypedType[]
        local argTypes = {}
        for i, x in ipairs(self.args) do
            argTypes[i] = x:getType()
        end
        eqs[#eqs + 1] = newEquation(self,
            TyFunc.new(self.location, argTypes, self.type_),
            defType)
        for _, arg in ipairs(self.args) do
            local newEqs, aerr = arg:appendEquations(eqs, loc, localDefs, ctx, stack)
            if aerr ~= nil then
                return nil, aerr
            end
            ---@cast newEqs -nil
            eqs = newEqs
        end
    end
    if self.declaredType ~= nil then
        eqs[#eqs + 1] = newEquation(self, self.type_, self.declaredType)
    end
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyPOption:appendBytecode(ops, locations, binary, hash)
    for _, arg in ipairs(self.args) do
        ops, locations = arg:appendBytecode(ops, locations, binary, hash)
    end
    return bytecode.appendMakePattern(
        bytecode.PATTERN_KIND_DATA_OPTION,
        self:name(),
        #self.args, self.location, ops, locations, binary, hash)
end

return { TyPOption = TyPOption }
