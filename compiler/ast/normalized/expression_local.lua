local NormExpression = require("compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("compiler.ast.normalized.module")
local TyLocal = require("compiler.ast.typed.expression_local").TyLocal

---A reference to a pattern-bound local. `predecessor` is the parsed-side node
---that originated this local; it is used by lambda lifting to redirect its
---successor when the local is replaced.
---@class NLocal : NormExpression
---@field kind "NLocal"
---@field location Location
---@field name Identifier
---@field target NormPattern|nil
---@field predecessor any|nil
local NLocal = setmetatable({}, { __index = NormExpression })
NLocal.__index = NLocal

---@param location Location
---@param name Identifier
---@param target NormPattern|nil
---@param predecessor any|nil
---@return NLocal
function NLocal.new(location, name, target, predecessor)
    return setmetatable({
        kind = "NLocal",
        location = location,
        name = name,
        target = target,
        predecessor = predecessor,
    }, NLocal)
end

---@param f fun(stmt: NormStatement)
function NLocal:iterate(f)
    f(self)
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NLocal:flattenLambdas(parentName, m, locals)
    local lp = locals[self.name]
    if lp ~= nil then
        self.target = lp
    end
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NLocal:replaceLocals(replace)
    local r = replace[self.name]
    if r ~= nil then
        if self.predecessor ~= nil and self.predecessor.setSuccessor ~= nil then
            self.predecessor:setSuccessor(r)
        end
        return r
    end
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NLocal:extractUsedLocalsSet(definedLocals, usedLocals)
    if definedLocals[self.name] ~= nil then
        usedLocals[self.name] = true
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
function NLocal:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    if self.target == nil then
        return nil, string.format("local variable `%s` not resolved", tostring(self.name))
    end
    local successor = self.target.successor
    ---@cast successor TypedPattern|nil
    return self:setSuccessor(TyLocal.new(ctx, self.location, self.name, successor))
end

return { NLocal = NLocal }
