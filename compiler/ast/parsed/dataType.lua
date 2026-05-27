local Statement = require("lunar.compiler.ast.parsed.defines").Statement
local makeFullIdentifier = require("lunar.compiler.ast.misc").makeFullIdentifier
local DataOption = require("lunar.compiler.ast.parsed.type_data").DataOption
local Definition = require("lunar.compiler.ast.parsed.definition").Definition
local Constructor = require("lunar.compiler.ast.parsed.expression_constructor").Constructor
local Var = require("lunar.compiler.ast.parsed.expression_var").Var
local PNamed = require("lunar.compiler.ast.parsed.pattern_named").PNamed
local TFunc = require("lunar.compiler.ast.parsed.type_func").TFunc
local TParameter = require("lunar.compiler.ast.parsed.type_parameter").TParameter
local TData = require("lunar.compiler.ast.parsed.type_data").TData
local Alias = require("lunar.compiler.ast.parsed.alias").Alias

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

---@class DataTypeOption : Statement
---@field kind "DataTypeOption"
---@field location Location
---@field hidden boolean
---@field name Identifier
---@field values DataTypeValue[]
---@field nameLocation Location
local DataTypeOption = setmetatable({}, { __index = Statement })
DataTypeOption.__index = DataTypeOption

---@param location Location
---@param hidden boolean
---@param name Identifier
---@param values DataTypeValue[]
---@param nameLocation Location
---@return DataTypeOption
function DataTypeOption.new(location, hidden, name, values, nameLocation)
    return setmetatable({
        kind = "DataTypeOption",
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

---Build the `DataOption` description that lives inside the resulting `TData` type.
---@return DataOption
function DataTypeOption:dataOption()
    local types = {}
    for i, v in ipairs(self.values) do
        types[i] = v.type
    end
    return DataOption.new(self.name, self.hidden, types, self.nameLocation)
end

---Build the constructor `Definition` corresponding to this option.
---@param moduleName QualifiedIdentifier
---@param dataName Identifier
---@param dataType Type
---@param hidden boolean
---@return Definition
function DataTypeOption:constructor(moduleName, dataName, dataType, hidden)

    local type_ = dataType
    if #self.values > 0 then
        local paramTypes = {}
        for i, v in ipairs(self.values) do
            paramTypes[i] = v.type
        end
        ---@type Type
        type_ = assert(TFunc.new(self.location, paramTypes, dataType))
    end

    local args = {}
    for i, v in ipairs(self.values) do
        args[i] = Var.new(self.location, "_" .. v.name)
    end
    local body = Constructor.new(
        self.location, moduleName, dataName, self.name, self.nameLocation, args)

    local params = {}
    for i, v in ipairs(self.values) do
        params[i] = PNamed.new(self.location, "_" .. v.name, v.location)
    end

    return Definition.new(
        self.location, self.hidden or hidden, self.name,
        self.nameLocation, params, body, type_)
end

---@class DataType : Statement
---@field kind "DataType"
---@field location Location
---@field hidden boolean
---@field name Identifier
---@field params Identifier[]
---@field options DataTypeOption[]
---@field nameLocation Location
---@field docComment DocComment|nil
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
        docComment = nil,
    }, DataType)
end

---@param f fun(stmt: Statement)
function DataType:iterate(f)
    f(self)
    for _, opt in ipairs(self.options) do
        opt:iterate(f)
    end
end

---Lower this data type definition into an alias + per-option constructors.
---@param moduleName QualifiedIdentifier
---@return Alias dataAlias
---@return Definition[] defs
function DataType:flatten(moduleName)

    local typeArgs = {}
    for i, p in ipairs(self.params) do
        typeArgs[i] = TParameter.new(self.location, p)
    end
    local options = {}
    for i, opt in ipairs(self.options) do
        options[i] = opt:dataOption()
    end
    local type_ = TData.new(
        self.location, makeFullIdentifier(moduleName, self.name),
        typeArgs, options, self.nameLocation)
    local dataAlias = Alias.new(
        self.location, self.hidden, self.name, self.params, type_,
        self.nameLocation)
    local defs = {}
    for i, opt in ipairs(self.options) do
        defs[i] = opt:constructor(moduleName, self.name, type_, self.hidden)
    end
    return dataAlias, defs
end

return {
    DataType = DataType,
    DataTypeOption = DataTypeOption,
    DataTypeValue = DataTypeValue,
}
