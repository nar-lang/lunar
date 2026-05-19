local NormType = require("compiler.ast.normalized.type").NormType

---@class NTUnit : NormType
---@field kind "NTUnit"
---@field location Location
local NTUnit = setmetatable({}, { __index = NormType })
NTUnit.__index = NTUnit

---@param location Location
---@return NTUnit
function NTUnit.new(location)
    return setmetatable({
        kind = "NTUnit",
        location = location,
    }, NTUnit)
end

---@param f fun(stmt: NormStatement)
function NTUnit:iterate(f)
    f(self)
end

return { NTUnit = NTUnit }
