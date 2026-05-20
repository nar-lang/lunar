local Expression = require("compiler.ast.parsed.expression").Expression
local NFunction = require("compiler.ast.normalized.expression_function").NFunction
local NPNamed = require("compiler.ast.normalized.pattern_named").NPNamed
local cloneMap = require("compiler.ast.parsed.utils").cloneMap

---@class Function : Expression
---@field kind "Function"
---@field location Location
---@field name Identifier
---@field nameLocation Location
---@field params Pattern[]
---@field body Expression
---@field declaredType Type|nil
---@field nested Expression
local Function = setmetatable({}, { __index = Expression })
Function.__index = Function

---@param location Location
---@param name Identifier
---@param nameLocation Location
---@param params Pattern[]
---@param body Expression
---@param declaredType Type|nil
---@param nested Expression
---@return Function
function Function.new(location, name, nameLocation, params, body, declaredType, nested)
    return setmetatable({
        kind = "Function",
        location = location,
        name = name,
        nameLocation = nameLocation,
        params = params or {},
        body = body,
        declaredType = declaredType,
        nested = nested,
    }, Function)
end

---@param f fun(stmt: Statement)
function Function:iterate(f)
    f(self)
    for _, p in ipairs(self.params) do
        p:iterate(f)
    end
    if self.body ~= nil then
        self.body:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Function:normalize(locals, modules, module, normalizedModule)
    local innerLocals = cloneMap(locals)
    innerLocals[self.name] = NPNamed.new(self.nameLocation, nil, self.name)
    local params = {}
    for i, param in ipairs(self.params) do
        local nParam, err = param:normalize(innerLocals, modules, module, normalizedModule)
        if nParam == nil then
            return nil, err
        end
        params[i] = nParam
    end
    local body, err = self.body:normalize(innerLocals, modules, module, normalizedModule)
    if body == nil then
        return nil, err
    end
    local nested, err2 = self.nested:normalize(innerLocals, modules, module, normalizedModule)
    if nested == nil then
        return nil, err2
    end
    ---@type NormType|nil
    local declaredType
    if self.declaredType ~= nil then
        local nType, err3 = self.declaredType:normalize(modules, module, nil)
        if err3 ~= nil then
            return nil, err3
        end
        ---@cast nType -nil
        declaredType = nType
    end
    return self:setSuccessor(
        NFunction.new(self.location, self.name, params, body, declaredType, nested, self)), nil
end

return { Function = Function }
