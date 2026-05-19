local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")

---@class NCall : NormExpression
---@field kind "NCall"
---@field location Location
---@field name FullIdentifier
---@field args NormExpression[]
local NCall = setmetatable({}, { __index = NormExpression })
NCall.__index = NCall

---@param location Location
---@param name FullIdentifier
---@param args NormExpression[]
---@return NCall
function NCall.new(location, name, args)
    return setmetatable({
        kind = "NCall",
        location = location,
        name = name,
        args = args or {},
    }, NCall)
end

---@param f fun(stmt: NormStatement)
function NCall:iterate(f)
    f(self)
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
function NCall:flattenLambdas(parentName, m, locals)
    for i, a in ipairs(self.args) do
        self.args[i] = a:flattenLambdas(parentName, m, locals)
    end
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NCall:replaceLocals(replace)
    for i, a in ipairs(self.args) do
        self.args[i] = a:replaceLocals(replace)
    end
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NCall:extractUsedLocalsSet(definedLocals, usedLocals)
    for _, a in ipairs(self.args) do
        a:extractUsedLocalsSet(definedLocals, usedLocals)
    end
end

return { NCall = NCall }
