local Pattern = require("compiler.ast.parsed.pattern").Pattern
local NPList = require("compiler.ast.normalized.pattern_list").NPList
local joinErrorList = require("compiler.ast.parsed.defines").joinErrorList

---@class PList : Pattern
---@field kind "PList"
---@field location Location
---@field items Pattern[]
---@field declaredType Type|nil
local PList = setmetatable({}, { __index = Pattern })
PList.__index = PList

---@param location Location
---@param items Pattern[]
---@return PList
function PList.new(location, items)
    return setmetatable({
        kind = "PList",
        location = location,
        items = items or {},
    }, PList)
end

---@param f fun(stmt: Statement)
function PList:iterate(f)
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
function PList:normalize(locals, modules, module, normalizedModule)
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
    return self:setSuccessor(NPList.new(self.location, declaredType, items)),
        joinErrorList(errors)
end

return { PList = PList }
