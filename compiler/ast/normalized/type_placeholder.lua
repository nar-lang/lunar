local NormType = require("lunar.compiler.ast.normalized.type").NormType

---Placeholder for a recursive named type during the parsed→normalized
---lowering. Looks up a real type from the placeholder map by name.
---@class NTPlaceholder : NormType
---@field kind "NTPlaceholder"
---@field location Location
---@field name FullIdentifier
local NTPlaceholder = setmetatable({}, { __index = NormType })
NTPlaceholder.__index = NTPlaceholder

---@param name FullIdentifier
---@return NTPlaceholder
function NTPlaceholder.new(name)
    return setmetatable({
        kind = "NTPlaceholder",
        location = nil,
        name = name,
    }, NTPlaceholder)
end

---@param f fun(stmt: NormStatement)
function NTPlaceholder:iterate(f)
    f(self)
end

---Returns the cached typed type registered under this placeholder name, or
---nil (registering the slot for later assignment by the data definition).
---@param ctx SolvingContext
---@param params TypeParamsMap
---@param source boolean
---@param placeholders PlaceholderMap|nil
---@return TypedType|nil t
---@return string|nil err
function NTPlaceholder:annotate(ctx, params, source, placeholders)
    if placeholders == nil then
        return nil, nil
    end
    local p = placeholders[self.name]
    if p ~= nil then
        return p, nil
    end
    placeholders[self.name] = nil
    return nil, nil
end

return { NTPlaceholder = NTPlaceholder }
