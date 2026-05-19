local Type = require("compiler.ast.parsed.type").Type
local NTData = require("compiler.ast.normalized.type_data").NTData
local NDataOption = require("compiler.ast.normalized.type_data").NDataOption
local NTPlaceholder = require("compiler.ast.normalized.type_placeholder").NTPlaceholder

---@class DataOption
---@field name Identifier
---@field hidden boolean
---@field values Type[]
---@field nameLocation Location
local DataOption = {}
DataOption.__index = DataOption

---@param name Identifier
---@param hidden boolean
---@param values Type[]
---@param nameLocation Location
---@return DataOption
function DataOption.new(name, hidden, values, nameLocation)
    return setmetatable({
        name = name,
        hidden = hidden == true,
        values = values or {},
        nameLocation = nameLocation,
    }, DataOption)
end

---@class TData : Type
---@field kind "TData"
---@field location Location
---@field name FullIdentifier
---@field args Type[]
---@field options DataOption[]
---@field nameLocation Location
local TData = setmetatable({}, { __index = Type })
TData.__index = TData

---@param location Location
---@param name FullIdentifier
---@param args Type[]
---@param options DataOption[]
---@param nameLocation Location
---@return TData
function TData.new(location, name, args, options, nameLocation)
    return setmetatable({
        kind = "TData",
        location = location,
        name = name,
        args = args or {},
        options = options or {},
        nameLocation = nameLocation,
    }, TData)
end

---@param f fun(stmt: Statement)
function TData:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
    for _, opt in ipairs(self.options) do
        for _, v in ipairs(opt.values) do
            v:iterate(f)
        end
    end
end

---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param namedTypes NamedTypeMap|nil
---@return NormType|nil
---@return string|nil error
function TData:normalize(modules, module, namedTypes)
    if namedTypes == nil then
        namedTypes = {}
    end
    local cached = namedTypes[self.name]
    if cached ~= nil then
        return cached, nil
    end
    namedTypes[self.name] = NTPlaceholder.new(self.name)

    local args = {}
    for i, a in ipairs(self.args) do
        local na, err = a:normalize(modules, module, namedTypes)
        if err ~= nil then
            return nil, err
        end
        args[i] = na
    end
    local options = {}
    for i, opt in ipairs(self.options) do
        local values = {}
        for j, v in ipairs(opt.values) do
            local nv, err = v:normalize(modules, module, namedTypes)
            if err ~= nil then
                return nil, err
            end
            values[j] = nv
        end
        options[i] = NDataOption.new(opt.name, opt.hidden, values)
    end
    return self:setSuccessor(NTData.new(self.location, self.name, args, options)), nil
end

---@param params table<Identifier, Type>
---@param loc Location
---@return Type|nil
---@return string|nil error
function TData:applyArgs(params, loc)
    local args = {}
    for i, a in ipairs(self.args) do
        local na, err = a:applyArgs(params, loc)
        if err ~= nil then
            return nil, err
        end
        args[i] = na
    end
    return TData.new(loc, self.name, args, self.options, self.nameLocation), nil
end

return { TData = TData, DataOption = DataOption }
