local Type = require("lunar.compiler.ast.parsed.type").Type
local NTNative = require("lunar.compiler.ast.normalized.type_native").NTNative

---@class TNative : Type
---@field kind "TNative"
---@field location Location
---@field name FullIdentifier
---@field args Type[]
---@field nameLocation Location
local TNative = setmetatable({}, { __index = Type })
TNative.__index = TNative

---@param location Location
---@param name FullIdentifier
---@param args Type[]
---@param nameLocation Location
---@return TNative
function TNative.new(location, name, args, nameLocation)
    return setmetatable({
        kind = "TNative",
        location = location,
        name = name,
        args = args or {},
        nameLocation = nameLocation,
    }, TNative)
end

---@param f fun(stmt: Statement)
function TNative:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
end

---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param namedTypes NamedTypeMap|nil
---@return NormType|nil
---@return string|nil error
function TNative:normalize(modules, module, namedTypes)
    local args = {}
    for i, a in ipairs(self.args) do
        local na, err = a:normalize(modules, module, namedTypes)
        if err ~= nil then
            return nil, err
        end
        ---@cast na -nil
        args[i] = na
    end
    return self:setSuccessor(NTNative.new(self.location, self.name, args)), nil
end

---@param params table<Identifier, Type>
---@param loc Location
---@return Type|nil
---@return string|nil error
function TNative:applyArgs(params, loc)
    local args = {}
    for i, a in ipairs(self.args) do
        local na, err = a:applyArgs(params, loc)
        if err ~= nil then
            return nil, err
        end
        ---@cast na -nil
        args[i] = na
    end
    return TNative.new(loc, self.name, args, self.nameLocation), nil
end

return { TNative = TNative }
