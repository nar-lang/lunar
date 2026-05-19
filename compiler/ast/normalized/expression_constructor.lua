local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")

---@class NConstructor : NormExpression
---@field kind "NConstructor"
---@field location Location
---@field moduleName QualifiedIdentifier
---@field dataName Identifier
---@field optionName Identifier
---@field args NormExpression[]
local NConstructor = setmetatable({}, { __index = NormExpression })
NConstructor.__index = NConstructor

---@param location Location
---@param moduleName QualifiedIdentifier
---@param dataName Identifier
---@param optionName Identifier
---@param args NormExpression[]
---@return NConstructor
function NConstructor.new(location, moduleName, dataName, optionName, args)
    return setmetatable({
        kind = "NConstructor",
        location = location,
        moduleName = moduleName,
        dataName = dataName,
        optionName = optionName,
        args = args or {},
    }, NConstructor)
end

---@param f fun(stmt: NormStatement)
function NConstructor:iterate(f)
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
function NConstructor:flattenLambdas(parentName, m, locals)
    for i, a in ipairs(self.args) do
        self.args[i] = a:flattenLambdas(parentName, m, locals)
    end
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NConstructor:replaceLocals(replace)
    for i, a in ipairs(self.args) do
        self.args[i] = a:replaceLocals(replace)
    end
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NConstructor:extractUsedLocalsSet(definedLocals, usedLocals)
    for _, a in ipairs(self.args) do
        a:extractUsedLocalsSet(definedLocals, usedLocals)
    end
end

return { NConstructor = NConstructor }
