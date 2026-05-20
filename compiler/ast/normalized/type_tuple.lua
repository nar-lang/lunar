local NormType = require("lunar.compiler.ast.normalized.type").NormType
local TyTupleType = require("lunar.compiler.ast.typed.type_tuple").TyTupleType

---@class NTTuple : NormType
---@field kind "NTTuple"
---@field location Location
---@field items NormType[]
local NTTuple = setmetatable({}, { __index = NormType })
NTTuple.__index = NTTuple

---@param location Location
---@param items NormType[]
---@return NTTuple
function NTTuple.new(location, items)
    return setmetatable({
        kind = "NTTuple",
        location = location,
        items = items or {},
    }, NTTuple)
end

---@param f fun(stmt: NormStatement)
function NTTuple:iterate(f)
    f(self)
    for _, it in ipairs(self.items) do
        if it ~= nil then
            it:iterate(f)
        end
    end
end

---@param ctx SolvingContext
---@param params TypeParamsMap
---@param source boolean
---@param placeholders PlaceholderMap|nil
---@return TypedType|nil t
---@return string|nil err
function NTTuple:annotate(ctx, params, source, placeholders)
    ---@type TypedType[]
    local items = {}
    for i, t in ipairs(self.items) do
        if t == nil then
            return nil, "tuple item type is not declared"
        end
        local x, err = t:annotate(ctx, params, source, placeholders)
        if err ~= nil then
            return nil, err
        end
        ---@cast x -nil
        items[i] = x
    end
    return self:setSuccessor(TyTupleType.new(self.location, items))
end

return { NTTuple = NTTuple }
