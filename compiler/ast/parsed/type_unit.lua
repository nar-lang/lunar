local Type = require("compiler.ast.parsed.type").Type

---@class TUnit : Type
---@field kind "TUnit"
---@field location Location
local TUnit = setmetatable({}, { __index = Type })
TUnit.__index = TUnit

---@param location Location
---@return TUnit
function TUnit.new(location)
    return setmetatable({
        kind = "TUnit",
        location = location,
    }, TUnit)
end

---@param f fun(stmt: Statement)
function TUnit:iterate(f)
    f(self)
end

---@return nil
---@return string
function TUnit:normalize()
    return nil, "TODO: normalize"
end

return { TUnit = TUnit }
