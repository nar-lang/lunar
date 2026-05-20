local Expression = require("lunar.compiler.ast.parsed.expression").Expression
local NLambda = require("lunar.compiler.ast.normalized.expression_lambda").NLambda

---@class Lambda : Expression
---@field kind "Lambda"
---@field location Location
---@field params Pattern[]
---@field returnType Type|nil
---@field body Expression
local Lambda = setmetatable({}, { __index = Expression })
Lambda.__index = Lambda

---@param location Location
---@param params Pattern[]
---@param returnType Type|nil
---@param body Expression
---@return Lambda
function Lambda.new(location, params, returnType, body)
    return setmetatable({
        kind = "Lambda",
        location = location,
        params = params or {},
        returnType = returnType,
        body = body,
    }, Lambda)
end

---@param f fun(stmt: Statement)
function Lambda:iterate(f)
    f(self)
    for _, p in ipairs(self.params) do
        p:iterate(f)
    end
    if self.returnType ~= nil then
        self.returnType:iterate(f)
    end
    if self.body ~= nil then
        self.body:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Lambda:normalize(locals, modules, module, normalizedModule)
    local params = {}
    for i, param in ipairs(self.params) do
        local nParam, err = param:normalize(locals, modules, module, normalizedModule)
        if nParam == nil then
            return nil, err
        end
        params[i] = nParam
    end
    local body, err = self.body:normalize(locals, modules, module, normalizedModule)
    if body == nil then
        return nil, err
    end
    return self:setSuccessor(NLambda.new(self.location, params, body)), nil
end

return { Lambda = Lambda }
