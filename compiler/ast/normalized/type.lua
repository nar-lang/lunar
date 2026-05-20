local NormStatement = require("lunar.compiler.ast.normalized.defines").NormStatement

---@class NormType : NormStatement
---@field kind string
---@field location Location
local NormType = setmetatable({}, { __index = NormStatement })
NormType.__index = NormType

---Annotate a normalized type into a typed type.
---@param ctx SolvingContext
---@param params TypeParamsMap
---@param source boolean
---@param placeholders PlaceholderMap|nil
---@return TypedType|nil t
---@return string|nil err
function NormType:annotate(ctx, params, source, placeholders)
    error("abstract method 'annotate' not implemented for kind=" .. tostring(self.kind), 2)
end

return { NormType = NormType }
