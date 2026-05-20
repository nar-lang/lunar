local Pattern = require("compiler.ast.parsed.pattern").Pattern
local NPTuple = require("compiler.ast.normalized.pattern_tuple").NPTuple
local joinErrorList = require("compiler.ast.parsed.defines").joinErrorList

---@class PTuple : Pattern
---@field kind "PTuple"
---@field location Location
---@field items Pattern[]
---@field declaredType Type|nil
local PTuple = setmetatable({}, { __index = Pattern })
PTuple.__index = PTuple

---@param location Location
---@param items Pattern[]
---@return PTuple
function PTuple.new(location, items)
    return setmetatable({
        kind = "PTuple",
        location = location,
        items = items or {},
    }, PTuple)
end

---@param f fun(stmt: Statement)
function PTuple:iterate(f)
    f(self)
    for _, item in ipairs(self.items) do
        item:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormPattern
---@return string|nil error
function PTuple:normalize(locals, modules, module, normalizedModule)
    local items = {}
    ---@type (string|nil)[]
    local errors = {}
    for i, item in ipairs(self.items) do
        local nItem, err = item:normalize(locals, modules, module, normalizedModule)
        if err ~= nil then
            errors[#errors + 1] = err
        end
        ---@cast nItem -nil
        items[i] = nItem
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
    return self:setSuccessor(NPTuple.new(self.location, declaredType, items)),
        joinErrorList(errors)
end

return { PTuple = PTuple }
