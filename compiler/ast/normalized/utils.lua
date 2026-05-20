---Helpers for the normalized AST.

---@param expr NormExpression
---@param definedLocals NormPatternMap
---@param params NormPatternMap
---@return Identifier[]
local function extractUsedLocals(expr, definedLocals, params)
    ---@type table<Identifier, true>
    local usedLocals = {}
    expr:extractUsedLocalsSet(definedLocals, usedLocals)
    ---@type Identifier[]
    local uniqueLocals = {}
    for k in pairs(usedLocals) do
        if params[k] == nil then
            uniqueLocals[#uniqueLocals + 1] = k
        end
    end
    table.sort(uniqueLocals)
    return uniqueLocals
end

---@param params NormPattern[]
---@return NormPatternMap
local function extractParamNames(params)
    ---@type NormPatternMap
    local paramNames = {}
    for _, p in ipairs(params) do
        p:extractLocals(paramNames)
    end
    return paramNames
end

---Safe wrapper for type annotation: returns nil for nil type.
---@param ctx SolvingContext
---@param type_ NormType|nil
---@param params TypeParamsMap
---@param source boolean
---@return TypedType|nil t
---@return string|nil err
local function annotateTypeSafe(ctx, type_, params, source)
    if type_ == nil then
        return nil, nil
    end
    return type_:annotate(ctx, params, source, nil)
end

---Find and lazily annotate a global definition (used by Global,
---Constructor, Update-global, and POption annotate methods).
---@param moduleName QualifiedIdentifier
---@param definitionName Identifier
---@param modules table<QualifiedIdentifier, NormModule>
---@param typedModules table<QualifiedIdentifier, TypedModule>
---@param stack TypedDefinition[]
---@param loc Location
---@return TypedDefinition|nil def
---@return string|nil err
local function getAnnotatedGlobal(moduleName, definitionName, modules, typedModules, stack, loc)
    local mod = modules[moduleName]
    if mod == nil then
        return nil, string.format("module `%s` not found", tostring(moduleName))
    end

    ---@type NormDefinition|nil
    local nDef = nil
    for _, d in ipairs(mod.definitions) do
        if d:name() == definitionName then
            nDef = d
            break
        end
    end
    if nDef == nil then
        return nil, string.format("definition `%s` not found", tostring(definitionName))
    end

    ---@type TypedDefinition|nil
    local def = nil
    for _, sd in ipairs(stack) do
        if sd.id == nDef.id then
            def = sd
            break
        end
    end

    if def == nil then
        local typedModule = typedModules[moduleName]
        if typedModule == nil then
            local errors = mod:annotate(modules, typedModules)
            if #errors > 0 then
                return nil, errors[1]
            end
            typedModule = typedModules[moduleName]
        end

        local existing = typedModule:findDefinition(nDef:name())
        if existing ~= nil then
            def = existing
        else
            local newDef, err = nDef:annotate(modules, typedModules, moduleName, stack)
            if err ~= nil then
                return newDef, err
            end
            ---@cast newDef -nil
            typedModule:addDefinition(newDef)
            def = newDef
        end
    end

    return def, nil
end

return {
    extractUsedLocals = extractUsedLocals,
    extractParamNames = extractParamNames,
    annotateTypeSafe = annotateTypeSafe,
    getAnnotatedGlobal = getAnnotatedGlobal,
}
