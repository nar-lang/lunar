local NormType = require("compiler.ast.normalized.type").NormType

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

return { NTNative = NTNative }
