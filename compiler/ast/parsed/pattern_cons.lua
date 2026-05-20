local Pattern = require("lunar.compiler.ast.parsed.pattern").Pattern
local NPCons = require("lunar.compiler.ast.normalized.pattern_cons").NPCons
local joinErrors = require("lunar.compiler.ast.parsed.defines").joinErrors

---@class PCons : Pattern
---@field kind "PCons"
---@field location Location
---@field head Pattern
---@field tail Pattern
---@field declaredType Type|nil
local PCons = setmetatable({}, { __index = Pattern })
PCons.__index = PCons

---@param location Location
---@param head Pattern
---@param tail Pattern
---@return PCons
function PCons.new(location, head, tail)
    return setmetatable({
        kind = "PCons",
        location = location,
        head = head,
        tail = tail,
    }, PCons)
end

---@param f fun(stmt: Statement)
function PCons:iterate(f)
    f(self)
    if self.head ~= nil then
        self.head:iterate(f)
    end
    if self.tail ~= nil then
        self.tail:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormPattern|nil
---@return string|nil error
function PCons:normalize(locals, modules, module, normalizedModule)
    local head, err1 = self.head:normalize(locals, modules, module, normalizedModule)
    local tail, err2 = self.tail:normalize(locals, modules, module, normalizedModule)
    if head == nil or tail == nil then
        return nil, joinErrors(err1, err2) or "failed to normalize cons pattern"
    end
    ---@type NormType|nil
    local declaredType
    ---@type string|nil
    local err3
    if self.declaredType ~= nil then
        declaredType, err3 = self.declaredType:normalize(modules, module, nil)
    end
    return self:setSuccessor(NPCons.new(self.location, declaredType, head, tail)),
        joinErrors(err1, err2, err3)
end

return { PCons = PCons }
