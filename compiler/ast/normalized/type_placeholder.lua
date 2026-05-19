local NormType = require("compiler.ast.normalized.type").NormType

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

return { NTPlaceholder = NTPlaceholder }
