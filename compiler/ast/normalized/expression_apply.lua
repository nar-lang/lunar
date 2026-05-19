local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")

---@class NApply : NormExpression
---@field kind "NApply"
---@field location Location
---@field func NormExpression
---@field args NormExpression[]
local NApply = setmetatable({}, { __index = NormExpression })
NApply.__index = NApply

---@param location Location
---@param func NormExpression
---@param args NormExpression[]
---@return NApply
function NApply.new(location, func, args)
    return setmetatable({
        kind = "NApply",
        location = location,
        func = func,
        args = args or {},
    }, NApply)
end

---@param f fun(stmt: NormStatement)
function NApply:iterate(f)
    f(self)
    if self.func ~= nil then
        self.func:iterate(f)
    end
    for _, a in ipairs(self.args) do
        if a ~= nil then
            a:iterate(f)
        end
    end
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NApply:flattenLambdas(parentName, m, locals)
    self.func = self.func:flattenLambdas(parentName, m, locals)
    for i, a in ipairs(self.args) do
        self.args[i] = a:flattenLambdas(parentName, m, locals)
    end
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NApply:replaceLocals(replace)
    self.func = self.func:replaceLocals(replace)
    for i, a in ipairs(self.args) do
        self.args[i] = a:replaceLocals(replace)
    end
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NApply:extractUsedLocalsSet(definedLocals, usedLocals)
    self.func:extractUsedLocalsSet(definedLocals, usedLocals)
    for _, a in ipairs(self.args) do
        a:extractUsedLocalsSet(definedLocals, usedLocals)
    end
end

return { NApply = NApply }
