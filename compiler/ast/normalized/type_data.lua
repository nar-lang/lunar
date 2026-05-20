local NormType = require("compiler.ast.normalized.type").NormType
local typedTData = require("compiler.ast.typed.type_data")
local TyData = typedTData.TyData
local TyDataOption = typedTData.TyDataOption
local makeDataOptionIdentifier = require("compiler.common.builtins").makeDataOptionIdentifier

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

---@param ctx SolvingContext
---@param params TypeParamsMap
---@param source boolean
---@param placeholders PlaceholderMap|nil
---@return TypedType|nil t
---@return string|nil err
function NTData:annotate(ctx, params, source, placeholders)
    if placeholders == nil then
        placeholders = {}
    end
    ---@type TypedType[]
    local args = {}
    for i, t in ipairs(self.args) do
        if t == nil then
            return nil, "type parameter is not declared"
        end
        local x, err = t:annotate(ctx, params, source, placeholders)
        if err ~= nil then
            return nil, err
        end
        ---@cast x -nil
        args[i] = x
    end
    local annotatedData = TyData.new(self.location, self.name, args, nil)
    placeholders[self.name] = annotatedData
    ---@type TyDataOption[]
    local options = {}
    for i, opt in ipairs(self.options) do
        ---@type TypedType[]
        local values = {}
        for j, v in ipairs(opt.values) do
            if v == nil then
                return nil, "option value type is not declared"
            end
            local x, err = v:annotate(ctx, params, source, placeholders)
            if err ~= nil then
                return nil, err
            end
            ---@cast x -nil
            -- A NTPlaceholder may legitimately resolve to nil when the
            -- placeholder is queried before its enclosing data type has
            -- registered itself. Skip the slot rather than inserting a
            -- nil hole (which would break `ipairs` iteration later).
            if x ~= nil then
                values[#values + 1] = x
            end
        end
        options[i] = TyDataOption.new(makeDataOptionIdentifier(self.name, opt.name), values)
    end
    annotatedData:setOptions(options)
    return self:setSuccessor(annotatedData)
end

return { NTData = NTData, NDataOption = NDataOption }
