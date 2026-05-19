local NormType = require("compiler.ast.normalized.type").NormType

---@class NDataOption
---@field name Identifier
---@field hidden boolean
---@field values NormType[]
local NDataOption = {}
NDataOption.__index = NDataOption

---@param name Identifier
---@param hidden boolean
---@param values NormType[]
---@return NDataOption
function NDataOption.new(name, hidden, values)
    return setmetatable({
        name = name,
        hidden = hidden == true,
        values = values or {},
    }, NDataOption)
end

---@class NTData : NormType
---@field kind "NTData"
---@field location Location
---@field name FullIdentifier
---@field args NormType[]
---@field options NDataOption[]
local NTData = setmetatable({}, { __index = NormType })
NTData.__index = NTData

---@param location Location
---@param name FullIdentifier
---@param args NormType[]
---@param options NDataOption[]
---@return NTData
function NTData.new(location, name, args, options)
    return setmetatable({
        kind = "NTData",
        location = location,
        name = name,
        args = args or {},
        options = options or {},
    }, NTData)
end

---@param f fun(stmt: NormStatement)
function NTData:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        if a ~= nil then
            a:iterate(f)
        end
    end
    for _, opt in ipairs(self.options) do
        if opt ~= nil then
            for _, v in ipairs(opt.values) do
                if v ~= nil then
                    v:iterate(f)
                end
            end
        end
    end
end

return { NTData = NTData, NDataOption = NDataOption }
