local NormType = require("compiler.ast.normalized.type").NormType

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

return { NTTuple = NTTuple }
