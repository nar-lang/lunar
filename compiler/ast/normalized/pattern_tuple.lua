local NormPattern = require("compiler.ast.normalized.pattern").NormPattern
local utils = require("compiler.ast.normalized.utils")
local TyPTuple = require("compiler.ast.typed.pattern_tuple").TyPTuple

---@class NPTuple : NormPattern
---@field kind "NPTuple"
---@field location Location
---@field declaredType NormType|nil
---@field items NormPattern[]
local NPTuple = setmetatable({}, { __index = NormPattern })
NPTuple.__index = NPTuple

---@param location Location
---@param declaredType NormType|nil
---@param items NormPattern[]
---@return NPTuple
function NPTuple.new(location, declaredType, items)
    return setmetatable({
        kind = "NPTuple",
        location = location,
        declaredType = declaredType,
        items = items or {},
    }, NPTuple)
end

---@param f fun(stmt: NormStatement)
function NPTuple:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    for _, it in ipairs(self.items) do
        if it ~= nil then
            it:iterate(f)
        end
    end
end

---@param locals NormPatternMap
function NPTuple:extractLocals(locals)
    for _, it in ipairs(self.items) do
        if it ~= nil then
            it:extractLocals(locals)
        end
    end
end

---@param ctx SolvingContext
---@param typeParams TypeParamsMap
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param moduleName QualifiedIdentifier
---@param typeMapSource boolean
---@param stack TypedDefinition[]
---@return TypedPattern|nil p
---@return string|nil err
function NPTuple:annotate(ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    ---@type TypedPattern[]
    local items = {}
    for i, x in ipairs(self.items) do
        local it, err = x:annotate(
            ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast it -nil
        items[i] = it
    end
    local declared, derr = utils.annotateTypeSafe(ctx, self.declaredType, typeParams, typeMapSource)
    if derr ~= nil then
        return nil, derr
    end
    ---@cast declared -nil
    local tuple, terr = TyPTuple.new(ctx, self.location, declared, items)
    if terr ~= nil then
        return nil, terr
    end
    ---@cast tuple -nil
    return self:setSuccessor(tuple)
end

return { NPTuple = NPTuple }
