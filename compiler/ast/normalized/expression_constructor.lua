local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")
local utils = require("compiler.ast.normalized.utils")
local TyConstructor = require("compiler.ast.typed.expression_constructor").TyConstructor
local makeFullIdentifier = require("compiler.common.builtins").makeFullIdentifier

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

---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param stack TypedDefinition[]
---@return TypedExpression|nil e
---@return string|nil err
function NConstructor:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)

    local ctorDef, err = utils.getAnnotatedGlobal(
        self.moduleName, self.optionName, modules, typedModules, stack, self.location)
    if err ~= nil then
        return nil, err
    end
    ---@cast ctorDef -nil
    local t = ctorDef.declaredType
    if t ~= nil and #ctorDef.params > 0 and t.kind == "TFunc" then
        ---@cast t TyFunc
        t = t.return_
    end
    ---@type TypedExpression[]
    local args = {}
    for i, x in ipairs(self.args) do
        local a, aerr = x:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
        if aerr ~= nil then
            return nil, aerr
        end
        ---@cast a -nil
        args[i] = a
    end
    ---@type TyData|nil
    local dt = nil
    if t ~= nil and t.kind == "TData" then
        ---@cast t TyData
        dt = t
    end
    local dataName = makeFullIdentifier(self.moduleName, self.dataName)
    return self:setSuccessor(TyConstructor.new(
        ctx, self.location, dataName, self.optionName, dt, args))
end

return { NConstructor = NConstructor }
