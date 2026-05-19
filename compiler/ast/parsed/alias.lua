local Statement = require("compiler.ast.parsed.defines").Statement

---@class Alias : Statement
---@field kind "Alias"
---@field location Location
---@field hidden boolean
---@field name Identifier
---@field params Identifier[]
---@field type Type?
---@field nameLocation Location
local Alias = setmetatable({}, { __index = Statement })
Alias.__index = Alias

---@param location Location
---@param hidden boolean
---@param name Identifier
---@param params Identifier[]
---@param type_ Type?
---@param nameLocation Location
---@return Alias
function Alias.new(location, hidden, name, params, type_, nameLocation)
    return setmetatable({
        kind = "Alias",
        location = location,
        hidden = hidden == true,
        name = name,
        params = params or {},
        type = type_,
        nameLocation = nameLocation,
    }, Alias)
end

---@param f fun(stmt: Statement)
function Alias:iterate(f)
    f(self)
    if self.type ~= nil then
        self.type:iterate(f)
    end
end

---@return nil
---@return string
function Alias:normalize()
    return nil, "TODO: normalize"
end

return { Alias = Alias }
