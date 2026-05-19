local Statement = require("compiler.ast.parsed.defines").Statement
local NormModule = require("compiler.ast.normalized.module").NormModule
local builtins = require("compiler.common.builtins")

---@class Module : Statement
---@field kind "Module"
---@field name QualifiedIdentifier
---@field location Location
---@field imports Import[]
---@field aliases Alias[]
---@field infixFns Infix[]
---@field definitions Definition[]
---@field dataTypes DataType[]
local Module = setmetatable({}, { __index = Statement })
Module.__index = Module

---@param name QualifiedIdentifier
---@param location Location
---@param imports Import[]
---@param aliases Alias[]
---@param infixFns Infix[]
---@param definitions Definition[]
---@param dataTypes DataType[]
---@return Module
function Module.new(name, location, imports, aliases, infixFns, definitions, dataTypes)
    return setmetatable({
        kind = "Module",
        name = name,
        location = location,
        imports = imports or {},
        aliases = aliases or {},
        infixFns = infixFns or {},
        definitions = definitions or {},
        dataTypes = dataTypes or {},
    }, Module)
end

---@param f fun(stmt: Statement)
function Module:iterate(f)
    f(self)
    for _, imp in ipairs(self.imports) do
        imp:iterate(f)
    end
    for _, a in ipairs(self.aliases) do
        a:iterate(f)
    end
    for _, i in ipairs(self.infixFns) do
        i:iterate(f)
    end
    for _, d in ipairs(self.definitions) do
        d:iterate(f)
    end
    for _, dt in ipairs(self.dataTypes) do
        dt:iterate(f)
    end
end

---Find a definition by qualified name. Returns (def, module, fullIdentifiers).
---@param modules table<QualifiedIdentifier, Module>|nil
---@param name QualifiedIdentifier
---@return Definition|nil
---@return Module|nil
---@return FullIdentifier[]
function Module:findDefinition(modules, name)
    -- 1. search in current module
    for _, def in ipairs(self.definitions) do
        if def.name == name then
            return def, self, { builtins.makeFullIdentifier(self.name, def.name) }
        end
    end

    local nameStr = tostring(name)
    ---@type integer|nil
    local lastDot
    for i = #nameStr, 1, -1 do
        if nameStr:sub(i, i) == "." then
            lastDot = i
            break
        end
    end
    local defName = nameStr
    local modName = ""
    if lastDot ~= nil then
        defName = nameStr:sub(lastDot + 1)
        modName = nameStr:sub(1, lastDot - 1)
    end

    if modules == nil then
        return nil, nil, {}
    end

    -- 2. search in imported modules
    for _, imp in ipairs(self.imports) do
        if imp:exposes(nameStr) then
            local impMod = modules[imp.moduleIdentifier]
            if impMod ~= nil then
                return impMod:findDefinition(nil, defName)
            end
        end
    end

    ---@type Definition|nil
    local rDef
    ---@type Module|nil
    local rModule
    ---@type FullIdentifier[]
    local rIdent = {}

    -- 3. search in all modules by qualified Name
    if modName ~= "" then
        local sub = modules[modName]
        if sub ~= nil then
            return sub:findDefinition(nil, defName)
        end
        -- 4. search in all modules by short Name suffix
        local suffix = "." .. modName
        for modId, sub2 in pairs(modules) do
            local modIdStr = tostring(modId)
            if #modIdStr >= #suffix and modIdStr:sub(-#suffix) == suffix then
                local d, m, ids = sub2:findDefinition(nil, defName)
                if #ids ~= 0 then
                    rDef = d
                    rModule = m
                    for _, id in ipairs(ids) do
                        rIdent[#rIdent + 1] = id
                    end
                end
            end
        end
        if #rIdent ~= 0 then
            return rDef, rModule, rIdent
        end
    end

    -- 5. search by definition Name as module Name
    if #defName > 0 then
        local first = defName:sub(1, 1)
        if first >= "A" and first <= "Z" then
            local suffix = "." .. defName
            for modId, sub2 in pairs(modules) do
                local modIdStr = tostring(modId)
                if modIdStr == defName or
                    (#modIdStr >= #suffix and modIdStr:sub(-#suffix) == suffix) then
                    local d, m, ids = sub2:findDefinition(nil, defName)
                    if #ids ~= 0 then
                        rDef = d
                        rModule = m
                        for _, id in ipairs(ids) do
                            rIdent[#rIdent + 1] = id
                        end
                    end
                end
            end
            if #rIdent ~= 0 then
                return rDef, rModule, rIdent
            end
        end
    end

    -- 6. search all modules
    if modName == "" then
        for _, sub2 in pairs(modules) do
            local d, m, ids = sub2:findDefinition(nil, defName)
            if #ids ~= 0 then
                rDef = d
                rModule = m
                for _, id in ipairs(ids) do
                    rIdent[#rIdent + 1] = id
                end
            end
        end
        if #rIdent ~= 0 then
            return rDef, rModule, rIdent
        end
    end

    return nil, nil, {}
end

---@param modules table<QualifiedIdentifier, Module>|nil
---@param name QualifiedIdentifier
---@param normalizedModule NormModule
---@return Definition|nil
---@return Module|nil
---@return FullIdentifier[]
function Module:findDefinitionAndAddDependency(modules, name, normalizedModule)
    local d, m, ids = self:findDefinition(modules, name)
    if #ids == 1 and m ~= nil and d ~= nil then
        normalizedModule:addDependencies(m.name, d.name)
    end
    return d, m, ids
end

---@param modules table<QualifiedIdentifier, Module>|nil
---@param name InfixIdentifier
---@return Infix|nil
---@return Module|nil
---@return FullIdentifier[]
function Module:findInfixFn(modules, name)
    -- 1. current module
    for _, inf in ipairs(self.infixFns) do
        if inf.name == name then
            return inf, self, { builtins.makeFullIdentifier(self.name, inf.alias) }
        end
    end
    if modules == nil then
        return nil, nil, {}
    end
    -- 2. imported modules
    for _, imp in ipairs(self.imports) do
        if imp:exposes(tostring(name)) then
            local impMod = modules[imp.moduleIdentifier]
            if impMod ~= nil then
                return impMod:findInfixFn(nil, name)
            end
        end
    end
    ---@type Infix|nil
    local rInfix
    ---@type Module|nil
    local rModule
    ---@type FullIdentifier[]
    local rIdent = {}
    -- 6. search all modules
    for _, sub in pairs(modules) do
        local fi, fm, fid = sub:findInfixFn(nil, name)
        if fid ~= nil and #fid > 0 then
            rInfix = fi
            rModule = fm
            for _, id in ipairs(fid) do
                rIdent[#rIdent + 1] = id
            end
        end
    end
    return rInfix, rModule, rIdent
end

---@param modules table<QualifiedIdentifier, Module>|nil
---@param name QualifiedIdentifier
---@param args Type[]
---@param loc Location
---@return Type|nil
---@return Module|nil
---@return FullIdentifier[]
---@return string|nil error
function Module:findType(modules, name, args, loc)
    -- 1. current module
    for _, a in ipairs(self.aliases) do
        if a.name == name then
            local t, id, err = a:inferType(self.name, args)
            if err ~= nil then
                return nil, nil, {}, err
            end
            return t, self, { id }, nil
        end
    end

    local nameStr = tostring(name)
    ---@type integer|nil
    local lastDot
    for i = #nameStr, 1, -1 do
        if nameStr:sub(i, i) == "." then
            lastDot = i
            break
        end
    end
    local typeName = nameStr
    local modName = ""
    if lastDot ~= nil then
        typeName = nameStr:sub(lastDot + 1)
        modName = nameStr:sub(1, lastDot - 1)
    end

    if modules == nil then
        return nil, nil, {}, nil
    end

    -- 2. imported modules
    for _, imp in ipairs(self.imports) do
        if imp:exposes(nameStr) then
            local impMod = modules[imp.moduleIdentifier]
            if impMod ~= nil then
                return impMod:findType(nil, typeName, args, loc)
            end
        end
    end

    ---@type Type|nil
    local rType
    ---@type Module|nil
    local rModule
    ---@type FullIdentifier[]
    local rIdent = {}

    -- 3-4. search by qualified / short mod name
    if modName ~= "" then
        local sub = modules[modName]
        if sub ~= nil then
            return sub:findType(nil, typeName, args, loc)
        end
        local suffix = "." .. modName
        for modId, sub2 in pairs(modules) do
            local modIdStr = tostring(modId)
            if #modIdStr >= #suffix and modIdStr:sub(-#suffix) == suffix then
                local t, m, ids, err = sub2:findType(nil, typeName, args, loc)
                if err ~= nil then
                    return nil, nil, {}, err
                end
                if #ids ~= 0 then
                    rType = t
                    rModule = m
                    for _, id in ipairs(ids) do
                        rIdent[#rIdent + 1] = id
                    end
                end
            end
        end
        if #rIdent ~= 0 then
            return rType, rModule, rIdent, nil
        end
    end

    -- 5. type name as module name (uppercase)
    if #typeName > 0 then
        local first = typeName:sub(1, 1)
        if first >= "A" and first <= "Z" then
            local suffix = "." .. typeName
            for modId, sub2 in pairs(modules) do
                local modIdStr = tostring(modId)
                if modIdStr == typeName or
                    (#modIdStr >= #suffix and modIdStr:sub(-#suffix) == suffix) then
                    local t, m, ids, err = sub2:findType(nil, typeName, args, loc)
                    if err ~= nil then
                        return nil, nil, {}, err
                    end
                    if #ids ~= 0 then
                        rType = t
                        rModule = m
                        for _, id in ipairs(ids) do
                            rIdent[#rIdent + 1] = id
                        end
                    end
                end
            end
            if #rIdent ~= 0 then
                return rType, rModule, rIdent, nil
            end
        end
    end

    -- 6. all modules
    if modName == "" then
        for _, sub2 in pairs(modules) do
            local t, m, ids, err = sub2:findType(nil, typeName, args, loc)
            if err ~= nil then
                return nil, nil, {}, err
            end
            if #ids ~= 0 then
                rType = t
                rModule = m
                for _, id in ipairs(ids) do
                    rIdent[#rIdent + 1] = id
                end
            end
        end
        if #rIdent ~= 0 then
            return rType, rModule, rIdent, nil
        end
    end

    return nil, nil, {}, nil
end

---Expand imports (call after generate).
---@param modules table<QualifiedIdentifier, Module>
---@return string[] errors
function Module:unwrapImports(modules)
    local errors = {}
    for _, imp in ipairs(self.imports) do
        local err = imp:unwrap(modules)
        if err ~= nil then
            errors[#errors + 1] = err
        end
    end
    return errors
end

---Lower data types into aliases + constructor definitions, then expand imports.
---@param modules table<QualifiedIdentifier, Module>
---@return string[] errors
function Module:generate(modules)
    for _, dt in ipairs(self.dataTypes) do
        local alias, defs = dt:flatten(self.name)
        self.aliases[#self.aliases + 1] = alias
        for _, d in ipairs(defs) do
            self.definitions[#self.definitions + 1] = d
        end
    end
    return self:unwrapImports(modules)
end

---Normalize this module (and its dependencies). Mutates `normalizedModules`.
---@param modules table<QualifiedIdentifier, Module>
---@param normalizedModules table<QualifiedIdentifier, NormModule>
---@return string[] errors
function Module:normalize(modules, normalizedModules)
    local errors = {}
    if normalizedModules[self.name] ~= nil then
        return errors
    end
    local o = NormModule.new(self.location, self.name, nil)
    for _, def in ipairs(self.definitions) do
        local nDef, params, defErrs = def:normalize(modules, self, o)
        if defErrs ~= nil then
            for _, e in ipairs(defErrs) do
                errors[#errors + 1] = e
            end
        end
        if nDef ~= nil then
            nDef:flattenLambdas(params, o)
            o:addDefinition(nDef)
        end
    end
    normalizedModules[self.name] = o
    for _, depModName in ipairs(o:getDependencies()) do
        local depModule = modules[depModName]
        if depModule == nil then
            errors[#errors + 1] = string.format("module `%s` not found", depModName)
        else
            local depErrs = depModule:normalize(modules, normalizedModules)
            for _, e in ipairs(depErrs) do
                errors[#errors + 1] = e
            end
        end
    end
    return errors
end

return { Module = Module }
