local Pattern = require("lunar.compiler.ast.parsed.pattern").Pattern
local NPOption = require("lunar.compiler.ast.normalized.pattern_option").NPOption
local joinErrorList = require("lunar.compiler.ast.parsed.defines").joinErrorList

---@class POption : Pattern
---@field kind "POption"
---@field location Location
---@field name QualifiedIdentifier
---@field args Pattern[]
---@field nameLocation Location
---@field declaredType Type|nil
local POption = setmetatable({}, { __index = Pattern })
POption.__index = POption

---@param location Location
---@param name QualifiedIdentifier
---@param args Pattern[]
---@param nameLocation Location
---@return POption
function POption.new(location, name, args, nameLocation)
    return setmetatable({
        kind = "POption",
        location = location,
        name = name,
        args = args or {},
        nameLocation = nameLocation,
    }, POption)
end

---@param f fun(stmt: Statement)
function POption:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        a:iterate(f)
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
function POption:normalize(locals, modules, module, normalizedModule)
    local def, mod, ids = module:findDefinitionAndAddDependency(modules, self.name, normalizedModule)
    if ids == nil or #ids == 0 then
        return nil, "data constructor not found"
    elseif #ids > 1 then
        return nil, string.format(
            "ambiguous data constructor `%s`, it can be one of %s. " ..
            "Use import or qualified identifer to clarify which one to use",
            self.name, table.concat(ids, ", "))
    end
    ---@cast def Definition
    ---@cast mod Module
    local values = {}
    ---@type (string|nil)[]
    local errors = {}
    for i, v in ipairs(self.args) do
        local nv, err = v:normalize(locals, modules, module, normalizedModule)
        if err ~= nil then
            errors[#errors + 1] = err
        end
        ---@cast nv -nil
        values[i] = nv
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
    return self:setSuccessor(NPOption.new(self.location, declaredType, mod.name, def.name, values)),
        joinErrorList(errors)
end

return { POption = POption }
