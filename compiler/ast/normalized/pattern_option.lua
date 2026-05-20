local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPOption : NormPattern
---@field kind "NPOption"
---@field location Location
---@field declaredType NormType|nil
---@field moduleName QualifiedIdentifier
---@field definitionName Identifier
---@field values NormPattern[]
local NPOption = setmetatable({}, { __index = NormPattern })
NPOption.__index = NPOption

---@param location Location
---@param declaredType NormType|nil
---@param moduleName QualifiedIdentifier
---@param definitionName Identifier
---@param values NormPattern[]
---@return NPOption
function NPOption.new(location, declaredType, moduleName, definitionName, values)
    return setmetatable({
        kind = "NPOption",
        location = location,
        declaredType = declaredType,
        moduleName = moduleName,
        definitionName = definitionName,
        values = values or {},
    }, NPOption)
end

---@param f fun(stmt: NormStatement)
function NPOption:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    for _, v in ipairs(self.values) do
        if v ~= nil then
            v:iterate(f)
        end
    end
end

---@param locals NormPatternMap
function NPOption:extractLocals(locals)
    for _, v in ipairs(self.values) do
        if v ~= nil then
            v:extractLocals(locals)
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
function NPOption:annotate(ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
    local utils = require("compiler.ast.normalized.utils")
    local TyPOption = require("compiler.ast.typed.pattern_option").TyPOption
    local def, derr = utils.getAnnotatedGlobal(
        self.moduleName, self.definitionName, modules, typedModules, stack, self.location)
    if derr ~= nil then
        return nil, derr
    end
    ---@cast def -nil
    ---@type TypedPattern[]
    local args = {}
    for i, x in ipairs(self.values) do
        local a, aerr = x:annotate(
            ctx, typeParams, modules, typedModules, moduleName, typeMapSource, stack)
        if aerr ~= nil then
            return nil, aerr
        end
        ---@cast a -nil
        args[i] = a
    end
    local declared, dtErr = utils.annotateTypeSafe(ctx, self.declaredType, typeParams, typeMapSource)
    if dtErr ~= nil then
        return nil, dtErr
    end
    ---@cast declared -nil
    local option, oerr = TyPOption.new(ctx, self.location, declared, def, args)
    if oerr ~= nil then
        return nil, oerr
    end
    ---@cast option -nil
    return self:setSuccessor(option)
end

return { NPOption = NPOption }
