local Type = require("compiler.ast.parsed.type").Type

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

---@return nil
---@return string
function TData:normalize()
    return nil, "TODO: normalize"
end

return { TData = TData, DataOption = DataOption }
