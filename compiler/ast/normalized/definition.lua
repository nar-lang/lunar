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

return { NormDefinition = NormDefinition }
