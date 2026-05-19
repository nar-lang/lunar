local Type = require("compiler.ast.parsed.type").Type

---@class TNative : Type
---@field kind "TNative"
---@field location Location
---@field name FullIdentifier
---@field args Type[]
---@field nameLocation Location
local TNative = setmetatable({}, { __index = Type })
TNative.__index = TNative

---@param location Location
---@param name FullIdentifier
---@param args Type[]
---@param nameLocation Location
---@return TNative
function TNative.new(location, name, args, nameLocation)
    return setmetatable({
        kind = "TNative",
        location = location,
        name = name,
        args = args or {},
        nameLocation = nameLocation,
    }, TNative)
end

---@param f fun(stmt: Statement)
function TNative:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
end

---@return nil
---@return string
function TNative:normalize()
    return nil, "TODO: normalize"
end

return { TNative = TNative }
