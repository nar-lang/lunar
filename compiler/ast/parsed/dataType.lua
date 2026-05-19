local Statement = require("compiler.ast.parsed.defines").Statement

---@class DataTypeValue
---@field location Location
---@field name Identifier
---@field type Type
---@field nameLocation Location
local DataTypeValue = {}
DataTypeValue.__index = DataTypeValue

---@param location Location
---@param name Identifier
---@param type_ Type
---@param nameLocation Location
---@return DataTypeValue
function DataTypeValue.new(location, name, type_, nameLocation)
    return setmetatable({
        location = location,
        name = name,
        type = type_,
        nameLocation = nameLocation,
    }, DataTypeValue)
end

---@class DataTypeOption
---@field location Location
---@field hidden boolean
---@field name Identifier
---@field values DataTypeValue[]
---@field nameLocation Location
local DataTypeOption = {}
DataTypeOption.__index = DataTypeOption

---@param location Location
---@param hidden boolean
---@param name Identifier
---@param values DataTypeValue[]
---@param nameLocation Location
---@return DataTypeOption
function DataTypeOption.new(location, hidden, name, values, nameLocation)
    return setmetatable({
        location = location,
        hidden = hidden == true,
        name = name,
        values = values or {},
        nameLocation = nameLocation,
    }, DataTypeOption)
end

---@param f fun(stmt: Statement)
function DataTypeOption:iterate(f)
    for _, v in ipairs(self.values) do
        if v.type ~= nil then
            v.type:iterate(f)
        end
    end
end

---@class DataType : Statement
---@field kind "DataType"
---@field location Location
---@field hidden boolean
---@field name Identifier
---@field params Identifier[]
---@field options DataTypeOption[]
---@field nameLocation Location
local DataType = setmetatable({}, { __index = Statement })
DataType.__index = DataType

---@param location Location
---@param hidden boolean
---@param name Identifier
---@param params Identifier[]
---@param options DataTypeOption[]
---@param nameLocation Location
---@return DataType
function DataType.new(location, hidden, name, params, options, nameLocation)
    return setmetatable({
        kind = "DataType",
        location = location,
        hidden = hidden == true,
        name = name,
        params = params or {},
        options = options or {},
        nameLocation = nameLocation,
    }, DataType)
end

---@param f fun(stmt: Statement)
function DataType:iterate(f)
    f(self)
    for _, opt in ipairs(self.options) do
        opt:iterate(f)
    end
end

---@return nil
---@return string
function DataType:normalize()
    return nil, "TODO: normalize"
end

return {
    DataType = DataType,
    DataTypeOption = DataTypeOption,
    DataTypeValue = DataTypeValue,
}
