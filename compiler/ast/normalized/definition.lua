local NormStatement = require("compiler.ast.normalized.defines").NormStatement
local Counters = require("compiler.ast.normalized.defines").Counters
-- Bring NormModule into LuaLS scope (safe: module.lua no longer requires
-- this file at top level so there is no load-time cycle).
local _NormModuleMod = require("compiler.ast.normalized.module")

---@class NormDefinition : NormStatement
---@field kind "NormDefinition"
---@field location Location
---@field id integer
---@field name_ Identifier
---@field nameLocation Location
---@field hidden boolean
---@field params_ NormPattern[]
---@field body_ NormExpression|nil
---@field declaredType NormType|nil
local NormDefinition = setmetatable({}, { __index = NormStatement })
NormDefinition.__index = NormDefinition

---@param location Location
---@param id integer
---@param hidden boolean
---@param name Identifier
---@param nameLocation Location
---@param params NormPattern[]
---@param body NormExpression|nil
---@param declaredType NormType|nil
---@return NormDefinition
function NormDefinition.new(location, id, hidden, name, nameLocation, params, body, declaredType)
    return setmetatable({
        kind = "NormDefinition",
        location = location,
        id = id,
        name_ = name,
        nameLocation = nameLocation,
        hidden = hidden == true,
        params_ = params or {},
        body_ = body,
        declaredType = declaredType,
    }, NormDefinition)
end

---@return Identifier
function NormDefinition:name()
    return self.name_
end

---@return NormPattern[]
function NormDefinition:params()
    return self.params_
end

---Return the (mandatory, post-normalize) body expression. Asserts non-nil.
---For inspection during the brief period before a body is assigned, read
---the `body_` field directly.
---@return NormExpression
function NormDefinition:body()
    local b = self.body_
    assert(b ~= nil, "NormDefinition body is nil; use the body_ field for pre-normalize inspection")
    ---@cast b NormExpression
    return b
end

---@param expr NormExpression
function NormDefinition:setBody(expr)
    self.body_ = expr
end

---@param params NormPatternMap
---@param o NormModule
function NormDefinition:flattenLambdas(params, o)
    Counters.lastLambdaId = 0
    if self.body_ ~= nil then
        self.body_ = self.body_:flattenLambdas(self.name_, o, params)
    end
end

---@param f fun(stmt: NormStatement)
function NormDefinition:iterate(f)
    f(self)
    for _, p in ipairs(self.params_) do
        if p ~= nil then
            p:iterate(f)
        end
    end
    if self.body_ ~= nil then
        self.body_:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---Annotate this normalized definition into a typed definition.
---Detects cycles via the `stack` (matches by `id`).
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param stack TypedDefinition[]|nil
---@return TypedDefinition|nil def
---@return string|nil err
function NormDefinition:annotate(modules, typedModules, moduleName, stack)
    stack = stack or {}
    for _, sd in ipairs(stack) do
        if sd.id == self.id then
            return sd, nil
        end
    end

    local TypedDefinition = require("compiler.ast.typed.definition").TypedDefinition
    local utils = require("compiler.ast.normalized.utils")

    local typedDef = TypedDefinition.new(
        self.location, self.id, self.hidden, self.name_, self.nameLocation)
    ---@type TypeParamsMap
    local localTypeParams = {}

    local annotatedDeclaredType, err = utils.annotateTypeSafe(
        typedDef.ctx, self.declaredType, {}, true)
    if err ~= nil then
        return nil, err
    end
    ---@cast annotatedDeclaredType -nil
    typedDef:setDeclaredType(annotatedDeclaredType)

    ---@type TypedPattern[]
    local params = {}
    for i, p in ipairs(self.params_) do
        local tp, perr = p:annotate(
            typedDef.ctx, localTypeParams, modules, typedModules, moduleName, true, stack)
        if perr ~= nil then
            return nil, perr
        end
        ---@cast tp -nil
        params[i] = tp
    end
    typedDef:setParams(params)

    stack[#stack + 1] = typedDef
    if self.body_ ~= nil then
        local body, berr = self.body_:annotate(
            typedDef.ctx, localTypeParams, modules, typedModules, moduleName, stack)
        if berr ~= nil then
            return nil, berr
        end
        ---@cast body -nil
        typedDef:setExpression(body)
    end
    stack[#stack] = nil

    self.successor = typedDef
    return typedDef, nil
end

return { NormDefinition = NormDefinition }
