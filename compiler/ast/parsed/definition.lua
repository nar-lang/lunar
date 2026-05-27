local Statement = require("lunar.compiler.ast.parsed.defines").Statement
local Counters = require("lunar.compiler.ast.normalized.defines").Counters
local NormDefinition = require("lunar.compiler.ast.normalized.definition").NormDefinition

---@class Definition : Statement
---@field kind "Definition"
---@field location Location
---@field hidden boolean
---@field name Identifier
---@field nameLocation Location
---@field params Pattern[]
---@field body Expression?
---@field declaredType Type|nil
---@field docComment DocComment|nil
---@field successor NormDefinition|nil
local Definition = setmetatable({}, { __index = Statement })
Definition.__index = Definition

---@param location Location
---@param hidden boolean
---@param name Identifier
---@param nameLocation Location
---@param params Pattern[]
---@param body Expression?
---@param declaredType Type|nil
---@return Definition
function Definition.new(location, hidden, name, nameLocation, params, body, declaredType)
    return setmetatable({
        kind = "Definition",
        location = location,
        hidden = hidden == true,
        name = name,
        nameLocation = nameLocation,
        params = params or {},
        body = body,
        declaredType = declaredType,
        docComment = nil,
    }, Definition)
end

---@param f fun(stmt: Statement)
function Definition:iterate(f)
    f(self)
    for _, p in ipairs(self.params) do
        p:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    if self.body ~= nil then
        self.body:iterate(f)
    end
end

---Normalize this definition. Returns the normalized definition, the parameter
---locals map (so the module can register them as roots), and a flat error list.
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormDefinition
---@return table<Identifier, NormPattern> paramLocals
---@return string[] errors
function Definition:normalize(modules, module, normalizedModule)
    Counters.lastDefinitionId = Counters.lastDefinitionId + 1
    local id = Counters.lastDefinitionId

    ---@type table<Identifier, NormPattern>
    local paramLocals = {}
    ---@type NormPattern[]
    local params = {}
    ---@type string[]
    local errors = {}

    for i, param in ipairs(self.params) do
        local nParam, err = param:normalize(paramLocals, modules, module, normalizedModule)
        if err ~= nil then
            errors[#errors + 1] = err
        end
        ---@cast nParam -nil
        params[i] = nParam
    end

    ---@type NormExpression|nil
    local body
    if self.body ~= nil then
        local locals = {}
        for k, v in pairs(paramLocals) do
            locals[k] = v
        end
        local nBody, err = self.body:normalize(locals, modules, module, normalizedModule)
        if err ~= nil then
            errors[#errors + 1] = err
        end
        ---@cast nBody -nil
        body = nBody
    end

    ---@type NormType|nil
    local declaredType
    if self.declaredType ~= nil then
        local nType, err = self.declaredType:normalize(modules, module, nil)
        if err ~= nil then
            errors[#errors + 1] = err
        end
        ---@cast nType -nil
        declaredType = nType
    end

    local nDef = NormDefinition.new(
        self.location, id, self.hidden, self.name,
        self.nameLocation, params, body, declaredType)
    self.successor = nDef
    return nDef, paramLocals, errors
end

return { Definition = Definition }
