local NormType = require("lunar.compiler.ast.normalized.type").NormType
local newTParameter = require("lunar.compiler.ast.typed.type_unbound").newTParameter

---@class NTParameter : NormType
---@field kind "NTParameter"
---@field location Location
---@field name Identifier
local NTParameter = setmetatable({}, { __index = NormType })
NTParameter.__index = NTParameter

---@param location Location
---@param name Identifier
---@return NTParameter
function NTParameter.new(location, name)
    return setmetatable({
        kind = "NTParameter",
        location = location,
        name = name,
    }, NTParameter)
end

---@param f fun(stmt: NormStatement)
function NTParameter:iterate(f)
    f(self)
end

---@param ctx SolvingContext
---@param params TypeParamsMap
---@param source boolean
---@param placeholders PlaceholderMap|nil
---@return TypedType|nil t
---@return string|nil err
function NTParameter:annotate(ctx, params, source, placeholders)
    local id = params[self.name]
    if id ~= nil then
        return self:setSuccessor(id)
    end
    if source then
        local r = newTParameter(ctx, self.location, self, self.name)
        params[self.name] = r
        return self:setSuccessor(r)
    end
    return nil, "unknown type parameter"
end

return { NTParameter = NTParameter }
