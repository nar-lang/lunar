local NormExpression = require("lunar.compiler.ast.normalized.expression").NormExpression

---@class NLambda : NormExpression
---@field kind "NLambda"
---@field location Location
---@field params NormPattern[]
---@field body NormExpression
local NLambda = setmetatable({}, { __index = NormExpression })
NLambda.__index = NLambda

---@param location Location
---@param params NormPattern[]
---@param body NormExpression
---@return NLambda
function NLambda.new(location, params, body)
    return setmetatable({
        kind = "NLambda",
        location = location,
        params = params or {},
        body = body,
    }, NLambda)
end

---@param f fun(stmt: NormStatement)
function NLambda:iterate(f)
    f(self)
    for _, p in ipairs(self.params) do
        if p ~= nil then
            p:iterate(f)
        end
    end
    if self.body ~= nil then
        self.body:iterate(f)
    end
end

local utils = require("lunar.compiler.ast.normalized.utils")

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NLambda:flattenLambdas(parentName, m, locals)
    local def, _, replacement = m:extractLambda(self.location, parentName, self.params, self.body, locals, "",
        self.location)
    ---@cast def NormDefinition
    ---@cast replacement NormExpression
    local paramNames = utils.extractParamNames(def:params())
    ---@type NormExpression
    local defBody = def:body()
    def:setBody(defBody:flattenLambdas(def:name(), m, paramNames))
    return replacement
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NLambda:replaceLocals(replace)
    self.body = self.body:replaceLocals(replace)
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NLambda:extractUsedLocalsSet(definedLocals, usedLocals)
    self.body:extractUsedLocalsSet(definedLocals, usedLocals)
end

return { NLambda = NLambda }
