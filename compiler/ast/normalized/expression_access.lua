local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")

---@class NAccess : NormExpression
---@field kind "NAccess"
---@field location Location
---@field record NormExpression
---@field fieldName Identifier
local NAccess = setmetatable({}, { __index = NormExpression })
NAccess.__index = NAccess

---@param location Location
---@param record NormExpression
---@param fieldName Identifier
---@return NAccess
function NAccess.new(location, record, fieldName)
    return setmetatable({
        kind = "NAccess",
        location = location,
        record = record,
        fieldName = fieldName,
    }, NAccess)
end

---@param f fun(stmt: NormStatement)
function NAccess:iterate(f)
    f(self)
    if self.record ~= nil then
        self.record:iterate(f)
    end
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NAccess:flattenLambdas(parentName, m, locals)
    self.record = self.record:flattenLambdas(parentName, m, locals)
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NAccess:replaceLocals(replace)
    self.record = self.record:replaceLocals(replace)
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NAccess:extractUsedLocalsSet(definedLocals, usedLocals)
    self.record:extractUsedLocalsSet(definedLocals, usedLocals)
end

return { NAccess = NAccess }
