local NormExpression = require("lunar.compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("lunar.compiler.ast.normalized.module")
local _NormDefinitionMod = require("lunar.compiler.ast.normalized.definition")
local utils = require("lunar.compiler.ast.normalized.utils")
local NPNamed = require("lunar.compiler.ast.normalized.pattern_named").NPNamed
local NLocal = require("lunar.compiler.ast.normalized.expression_local").NLocal
local NApply = require("lunar.compiler.ast.normalized.expression_apply").NApply
local NGlobal = require("lunar.compiler.ast.normalized.expression_global").NGlobal
local NLet = require("lunar.compiler.ast.normalized.expression_let").NLet
local Counters = require("lunar.compiler.ast.normalized.defines").Counters

---@class NFunction : NormExpression
---@field kind "NFunction"
---@field location Location
---@field name Identifier
---@field params NormPattern[]
---@field body NormExpression
---@field fnType NormType|nil
---@field nested NormExpression
---@field predecessor any
local NFunction = setmetatable({}, { __index = NormExpression })
NFunction.__index = NFunction

---@param location Location
---@param name Identifier
---@param params NormPattern[]
---@param body NormExpression
---@param fnType NormType|nil
---@param nested NormExpression
---@param predecessor any predecessor object with a `setSuccessor` method
---@return NFunction
function NFunction.new(location, name, params, body, fnType, nested, predecessor)
    return setmetatable({
        kind = "NFunction",
        location = location,
        name = name,
        params = params or {},
        body = body,
        fnType = fnType,
        nested = nested,
        predecessor = predecessor,
    }, NFunction)
end

---@param f fun(stmt: NormStatement)
function NFunction:iterate(f)
    f(self)
    for _, p in ipairs(self.params) do
        if p ~= nil then
            p:iterate(f)
        end
    end
    if self.body ~= nil then
        self.body:iterate(f)
    end
    if self.fnType ~= nil then
        self.fnType:iterate(f)
    end
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NFunction:flattenLambdas(parentName, m, locals)

    local lambdaDef, usedLocals, replacement = m:extractLambda(
        self.location, parentName, self.params, self.body, locals, self.name, self.location)
    ---@cast lambdaDef NormDefinition
    ---@cast usedLocals Identifier[]
    ---@cast replacement NormExpression

    if self.predecessor ~= nil and self.predecessor.setSuccessor ~= nil then
        self.predecessor:setSuccessor(lambdaDef:body())
    end

    if #usedLocals > 0 then
        local replName = string.format("_lmbd_closrue_%d", Counters.lastLambdaId)
        local replaceMap = {}

        ---@type NormExpression[]
        local closureArgs = {}
        for i, arg in ipairs(usedLocals) do
            closureArgs[i] = NLocal.new(self.location, arg, lambdaDef:params()[i], self.predecessor)
        end

        local selfName = "_self"
        local selfPattern = NPNamed.new(self.location, nil, selfName)
        lambdaDef:setBody(NLet.new(self.location,
            selfPattern,
            NApply.new(self.location, NGlobal.new(self.location, m.name, lambdaDef:name()), closureArgs),
            lambdaDef:body()))

        replaceMap[self.name] = NLocal.new(self.location, selfName, selfPattern, self.predecessor)
        lambdaDef:setBody(lambdaDef:body():replaceLocals(replaceMap))
        local paramNames = utils.extractParamNames(lambdaDef:params())
        lambdaDef:setBody(lambdaDef:body():flattenLambdas(lambdaDef:name(), m, paramNames))

        local patternName = NPNamed.new(self.location, nil, replName)
        replaceMap[self.name] = NLocal.new(self.location, replName, patternName, self.predecessor)
        local letNested = self.nested:replaceLocals(replaceMap)
        letNested = letNested:flattenLambdas(parentName, m, locals)
        return NLet.new(self.location, patternName, replacement, letNested)
    else
        local replaceMap = {}
        replaceMap[self.name] = replacement
        lambdaDef:setBody(lambdaDef:body():replaceLocals(replaceMap))
        local paramNames = utils.extractParamNames(lambdaDef:params())
        lambdaDef:setBody(lambdaDef:body():flattenLambdas(lambdaDef:name(), m, paramNames))
        local replacedLocals = self.nested:replaceLocals(replaceMap)
        return replacedLocals:flattenLambdas(parentName, m, locals)
    end
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NFunction:replaceLocals(replace)
    self.body = self.body:replaceLocals(replace)
    self.nested = self.nested:replaceLocals(replace)
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NFunction:extractUsedLocalsSet(definedLocals, usedLocals)
    self.body:extractUsedLocalsSet(definedLocals, usedLocals)
    self.nested:extractUsedLocalsSet(definedLocals, usedLocals)
end

return { NFunction = NFunction }
