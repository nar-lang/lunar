local Type = require("compiler.ast.parsed.type").Type

---@class TParameter : Type
---@field kind "TParameter"
---@field location Location
---@field name Identifier
local TParameter = setmetatable({}, { __index = Type })
TParameter.__index = TParameter

---@param location Location
---@param name Identifier
---@return TParameter
function TParameter.new(location, name)
    return setmetatable({
        kind = "TParameter",
        location = location,
        name = name,
    }, TParameter)
end

---@param f fun(stmt: Statement)
function TParameter:iterate(f)
    f(self)
end

---@return nil
---@return string
function TParameter:normalize()
    return nil, "TODO: normalize"
end

return { TParameter = TParameter }
