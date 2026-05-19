local Pattern = require("compiler.ast.parsed.pattern").Pattern

---@class PNamed : Pattern
---@field kind "PNamed"
---@field location Location
---@field name Identifier
---@field nameLocation Location
---@field declaredType Type|nil
local PNamed = setmetatable({}, { __index = Pattern })
PNamed.__index = PNamed

---@param location Location
---@param name Identifier
---@param nameLocation Location
---@return PNamed
function PNamed.new(location, name, nameLocation)
    return setmetatable({
        kind = "PNamed",
        location = location,
        name = name,
        nameLocation = nameLocation,
    }, PNamed)
end

---@param f fun(stmt: Statement)
function PNamed:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@return nil
---@return string
function PNamed:normalize()
    return nil, "TODO: normalize"
end

return { PNamed = PNamed }
