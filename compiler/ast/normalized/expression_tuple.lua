local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")

---@class NTuple : NormExpression
---@field kind "NTuple"
---@field location Location
---@field items NormExpression[]
local NTuple = setmetatable({}, { __index = NormExpression })
NTuple.__index = NTuple

---@param location Location
---@param items NormExpression[]
---@return NTuple
function NTuple.new(location, items)
    return setmetatable({
        kind = "NTuple",
        location = location,
        items = items or {},
    }, NTuple)
end

---@param f fun(stmt: NormStatement)
function NTuple:iterate(f)
    f(self)
    for _, item in ipairs(self.items) do
        if item ~= nil then
            item:iterate(f)
        end
    end
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NTuple:flattenLambdas(parentName, m, locals)
    for i, a in ipairs(self.items) do
        self.items[i] = a:flattenLambdas(parentName, m, locals)
    end
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NTuple:replaceLocals(replace)
    for i, a in ipairs(self.items) do
        self.items[i] = a:replaceLocals(replace)
    end
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NTuple:extractUsedLocalsSet(definedLocals, usedLocals)
    for _, it in ipairs(self.items) do
        it:extractUsedLocalsSet(definedLocals, usedLocals)
    end
end

return { NTuple = NTuple }
