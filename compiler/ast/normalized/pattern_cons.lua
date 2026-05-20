local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPCons : NormPattern
---@field kind "NPCons"
---@field location Location
---@field declaredType NormType|nil
---@field head NormPattern
---@field tail NormPattern
local NPCons = setmetatable({}, { __index = NormPattern })
NPCons.__index = NPCons

---@param location Location
---@param declaredType NormType|nil
---@param head NormPattern
---@param tail NormPattern
---@return NPCons
function NPCons.new(location, declaredType, head, tail)
    return setmetatable({
        kind = "NPCons",
        location = location,
        declaredType = declaredType,
        head = head,
        tail = tail,
    }, NPCons)
end

---@param f fun(stmt: NormStatement)
function NPCons:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    if self.head ~= nil then
        self.head:iterate(f)
    end
    if self.tail ~= nil then
        self.tail:iterate(f)
    end
end

---@param locals NormPatternMap
function NPCons:extractLocals(locals)
    if self.head ~= nil then
        self.head:extractLocals(locals)
    end
    if self.tail ~= nil then
        self.tail:extractLocals(locals)
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
function NPCons:annotate(ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    local utils = require("compiler.ast.normalized.utils")
    local TyPCons = require("compiler.ast.typed.pattern_cons").TyPCons
    local head, herr = self.head:annotate(
        ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    if herr ~= nil then
        return nil, herr
    end
    ---@cast head -nil
    local tail, terr = self.tail:annotate(
        ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    if terr ~= nil then
        return nil, terr
    end
    ---@cast tail -nil
    local declared, derr = utils.annotateTypeSafe(ctx, self.declaredType, typeParams, typeMapSource)
    if derr ~= nil then
        return nil, derr
    end
    ---@cast declared -nil
    return self:setSuccessor(TyPCons.new(ctx, self.location, declared, head, tail))
end

return { NPCons = NPCons }
