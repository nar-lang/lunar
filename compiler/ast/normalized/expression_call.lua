local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")
local TyCall = require("compiler.ast.typed.expression_call").TyCall

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

---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param stack TypedDefinition[]
---@return TypedExpression|nil e
---@return string|nil err
function NCall:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    ---@type TypedExpression[]
    local args = {}
    for i, x in ipairs(self.args) do
        local a, err = x:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast a -nil
        args[i] = a
    end
    local call, err = TyCall.new(ctx, self.location, self.name, args)
    if err ~= nil then
        return nil, err
    end
    ---@cast call -nil
    return self:setSuccessor(call)
end

return { NCall = NCall }
