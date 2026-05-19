local Expression = require("compiler.ast.parsed.expression").Expression
local NApply = require("compiler.ast.normalized.expression_apply").NApply

---@class Apply : Expression
---@field kind "Apply"
---@field location Location
---@field func Expression
---@field args Expression[]
local Apply = setmetatable({}, { __index = Expression })
Apply.__index = Apply

---@param location Location
---@param func Expression
---@param args Expression[]
---@return Apply
function Apply.new(location, func, args)
    return setmetatable({
        kind = "Apply",
        location = location,
        func = func,
        args = args or {},
    }, Apply)
end

---@param f fun(stmt: Statement)
function Apply:iterate(f)
    f(self)
    if self.func ~= nil then
        self.func:iterate(f)
    end
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Apply:normalize(locals, modules, module, normalizedModule)
    local fn, err = self.func:normalize(locals, modules, module, normalizedModule)
    if fn == nil then
        return nil, err
    end
    local args = {}
    for i, arg in ipairs(self.args) do
        local nArg, argErr = arg:normalize(locals, modules, module, normalizedModule)
        if nArg == nil then
            return nil, argErr
        end
        args[i] = nArg
    end
    return self:setSuccessor(NApply.new(self.location, fn, args)), nil
end

return { Apply = Apply }
