local Pattern = require("compiler.ast.parsed.pattern").Pattern

---@class PAny : Pattern
---@field kind "PAny"
---@field location Location
---@field declaredType Type|nil
local PAny = setmetatable({}, { __index = Pattern })
PAny.__index = PAny

---@param location Location
---@return PAny
function PAny.new(location)
    return setmetatable({
        kind = "PAny",
        location = location,
    }, PAny)
end

---@param f fun(stmt: Statement)
function PAny:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@return nil
---@return string
function PAny:normalize()
    return nil, "TODO: normalize"
end

return { PAny = PAny }
