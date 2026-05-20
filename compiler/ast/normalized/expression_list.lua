local NormExpression = require("lunar.compiler.ast.normalized.expression").NormExpression
local _NormModuleMod = require("lunar.compiler.ast.normalized.module")
local TyList = require("lunar.compiler.ast.typed.expression_list").TyList

---@class NList : NormExpression
---@field kind "NList"
---@field location Location
---@field items NormExpression[]
local NList = setmetatable({}, { __index = NormExpression })
NList.__index = NList

---@param location Location
---@param items NormExpression[]
---@return NList
function NList.new(location, items)
    return setmetatable({
        kind = "NList",
        location = location,
        items = items or {},
    }, NList)
end

---@param f fun(stmt: NormStatement)
function NList:iterate(f)
    f(self)
    for _, item in ipairs(self.items) do
        if item ~= nil then
            item:iterate(f)
        end
    end
end

---@param parentName Identifier
---@param m NormModule
---@param locals NormPatternMap
---@return NormExpression
function NList:flattenLambdas(parentName, m, locals)
    for i, a in ipairs(self.items) do
        self.items[i] = a:flattenLambdas(parentName, m, locals)
    end
    return self
end

---@param replace table<Identifier, NormExpression>
---@return NormExpression
function NList:replaceLocals(replace)
    for i, a in ipairs(self.items) do
        self.items[i] = a:replaceLocals(replace)
    end
    return self
end

---@param definedLocals NormPatternMap
---@param usedLocals table<Identifier, true>
function NList:extractUsedLocalsSet(definedLocals, usedLocals)
    for _, it in ipairs(self.items) do
        it:extractUsedLocalsSet(definedLocals, usedLocals)
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
function NList:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
    ---@type TypedExpression[]
    local items = {}
    for i, x in ipairs(self.items) do
        local it, err = x:annotate(ctx, typeParams, modules, typedModules, moduleName, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast it -nil
        items[i] = it
    end
    return self:setSuccessor(TyList.new(ctx, self.location, items))
end

return { NList = NList }
