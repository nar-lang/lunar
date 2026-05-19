local Expression = require("compiler.ast.parsed.expression").Expression
local NCall = require("compiler.ast.normalized.expression_call").NCall

---@class Call : Expression
---@field kind "Call"
---@field location Location
---@field name FullIdentifier
---@field args Expression[]
local Call = setmetatable({}, { __index = Expression })
Call.__index = Call

---@param location Location
---@param name FullIdentifier
---@param args Expression[]
---@return Call
function Call.new(location, name, args)
    return setmetatable({
        kind = "Call",
        location = location,
        name = name,
        args = args or {},
    }, Call)
end

---@param f fun(stmt: Statement)
function Call:iterate(f)
    f(self)
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
function Call:normalize(locals, modules, module, normalizedModule)
    local args = {}
    for i, arg in ipairs(self.args) do
        local nArg, err = arg:normalize(locals, modules, module, normalizedModule)
        if nArg == nil then
            return nil, err
        end
        args[i] = nArg
    end
    return self:setSuccessor(NCall.new(self.location, self.name, args)), nil
end

return { Call = Call }
