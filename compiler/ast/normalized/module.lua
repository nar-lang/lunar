local Counters = require("lunar.compiler.ast.normalized.defines").Counters
local utils = require("lunar.compiler.ast.normalized.utils")
local NPNamed = require("lunar.compiler.ast.normalized.pattern_named").NPNamed
local TypedModule = require("lunar.compiler.ast.typed.module").TypedModule
-- NormDefinition is required lazily inside extractLambda to avoid a
-- top-level require cycle (definition.lua requires this module so that
-- LuaLS can resolve `---@param o NormModule` on NormDefinition methods).

---@class NormModule
---@field location Location
---@field name QualifiedIdentifier
---@field dependencies table<QualifiedIdentifier, Identifier[]>
---@field definitions NormDefinition[]
local NormModule = {}
NormModule.__index = NormModule

---@param location Location
---@param name QualifiedIdentifier
---@param definitions NormDefinition[]|nil
---@return NormModule
function NormModule.new(location, name, definitions)
    return setmetatable({
        location = location,
        name = name,
        dependencies = {},
        definitions = definitions or {},
    }, NormModule)
end

---@param definition NormDefinition
function NormModule:addDefinition(definition)
    self.definitions[#self.definitions + 1] = definition
end

---@return QualifiedIdentifier[]
function NormModule:getDependencies()
    ---@type QualifiedIdentifier[]
    local keys = {}
    for k in pairs(self.dependencies) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

---@param modName QualifiedIdentifier
---@param identName Identifier
function NormModule:addDependencies(modName, identName)
    local arr = self.dependencies[modName]
    if arr == nil then
        arr = {}
        self.dependencies[modName] = arr
    end
    arr[#arr + 1] = identName
end

---@param loc Location
---@param parentName Identifier
---@param params NormPattern[]
---@param body NormExpression
---@param locals NormPatternMap
---@param name Identifier
---@param nameLocation Location
---@return NormDefinition lambdaDef
---@return Identifier[] usedLocals
---@return NormExpression replacement
function NormModule:extractLambda(loc, parentName, params, body, locals, name, nameLocation)
    -- Inline requires below break a top-level cycle:
    -- module <-> {definition, expression_global, expression_local, expression_apply}.
    local NormDefinition = require("lunar.compiler.ast.normalized.definition").NormDefinition
    local NGlobal = require("lunar.compiler.ast.normalized.expression_global").NGlobal
    local NLocal = require("lunar.compiler.ast.normalized.expression_local").NLocal
    local NApply = require("lunar.compiler.ast.normalized.expression_apply").NApply

    Counters.lastLambdaId = Counters.lastLambdaId + 1
    local lambdaName = string.format("_lmbd_%s_%d_%s", parentName, Counters.lastLambdaId, name)
    local paramNames = utils.extractParamNames(params)
    local usedLocals = utils.extractUsedLocals(body, locals, paramNames)
    Counters.lastDefinitionId = Counters.lastDefinitionId + 1

    ---@type NormPattern[]
    local localParams = {}
    for i, x in ipairs(usedLocals) do
        localParams[i] = NPNamed.new(loc, nil, x)
    end

    ---@type NormPattern[]
    local allParams = {}
    for _, p in ipairs(localParams) do
        allParams[#allParams + 1] = p
    end
    for _, p in ipairs(params) do
        allParams[#allParams + 1] = p
    end

    local lambdaDef = NormDefinition.new(loc, Counters.lastDefinitionId, true, lambdaName, nameLocation, allParams, body,
        nil)
    self.definitions[#self.definitions + 1] = lambdaDef

    ---@type NormExpression
    local replacement = NGlobal.new(loc, self.name, lambdaDef:name())

    if #usedLocals > 0 then
        ---@type NormExpression[]
        local args = {}
        for i, x in ipairs(usedLocals) do
            local lp = locals[x]
            args[i] = NLocal.new(loc, x, lp, nil)
        end
        replacement = NApply.new(loc, replacement, args)
    end

    return lambdaDef, usedLocals, replacement
end

---Annotate this module and all its dependencies into typed modules.
---Idempotent: returns nil errors if already annotated.
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@return string[]
function NormModule:annotate(modules, typedModules)
    ---@type string[]
    local errors = {}
    if typedModules[self.name] ~= nil then
        return errors
    end

    -- Recursively annotate dependencies first. Iterate sorted for
    -- deterministic processing.
    local depNames = self:getDependencies()
    for _, depName in ipairs(depNames) do
        if depName ~= self.name then
            local depModule = modules[depName]
            if depModule == nil then
                errors[#errors + 1] = string.format(
                    "module dependency `%s` not found", tostring(depName))
                return errors
            end
            local depErrors = depModule:annotate(modules, typedModules)
            if #depErrors > 0 then
                for _, e in ipairs(depErrors) do
                    errors[#errors + 1] = e
                end
                return errors
            end
        end
    end

    local o = TypedModule.new(self.location, self.name, self.dependencies, nil)
    typedModules[self.name] = o

    for i = 1, #self.definitions do
        local def = self.definitions[i]
        local typedDef, err = def:annotate(modules, typedModules, self.name, nil)
        if err ~= nil then
            errors[#errors + 1] = err
        else
            ---@cast typedDef -nil
            o:addDefinition(typedDef)
        end
    end

    return errors
end

return { NormModule = NormModule }
