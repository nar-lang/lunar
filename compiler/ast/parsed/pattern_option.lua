local Pattern = require("compiler.ast.parsed.pattern").Pattern

---@class POption : Pattern
---@field kind "POption"
---@field location Location
---@field name QualifiedIdentifier
---@field args Pattern[]
---@field nameLocation Location
---@field declaredType Type|nil
local POption = setmetatable({}, { __index = Pattern })
POption.__index = POption

---@param location Location
---@param name QualifiedIdentifier
---@param args Pattern[]
---@param nameLocation Location
---@return POption
function POption.new(location, name, args, nameLocation)
    return setmetatable({
        kind = "POption",
        location = location,
        name = name,
        args = args or {},
        nameLocation = nameLocation,
    }, POption)
end

---@param f fun(stmt: Statement)
function POption:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@return nil
---@return string
function POption:normalize()
    return nil, "TODO: normalize"
end

return { POption = POption }
