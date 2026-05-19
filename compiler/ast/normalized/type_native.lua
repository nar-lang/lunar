local NormType = require("compiler.ast.normalized.type").NormType
local TNative = require("compiler.ast.typed.type_native").TNative

---@class NTNative : NormType
---@field kind "NTNative"
---@field location Location
---@field name FullIdentifier
---@field args NormType[]
local NTNative = setmetatable({}, { __index = NormType })
NTNative.__index = NTNative

---@param location Location
---@param name FullIdentifier
---@param args NormType[]
---@return NTNative
function NTNative.new(location, name, args)
    return setmetatable({
        kind = "NTNative",
        location = location,
        name = name,
        args = args or {},
    }, NTNative)
end

---@param f fun(stmt: NormStatement)
function NTNative:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        if a ~= nil then
            a:iterate(f)
        end
    end
end

---@param ctx SolvingContext
---@param params TypeParamsMap
---@param source boolean
---@param placeholders PlaceholderMap|nil
---@return TypedType|nil t
---@return string|nil err
function NTNative:annotate(ctx, params, source, placeholders)
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
        args[i] = x
    end
    return self:setSuccessor(TNative.new(self.location, self.name, args))
end

return { NTNative = NTNative }
