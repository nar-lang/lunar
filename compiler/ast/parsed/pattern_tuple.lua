local Pattern = require("compiler.ast.parsed.pattern").Pattern

---@class PTuple : Pattern
---@field kind "PTuple"
---@field location Location
---@field items Pattern[]
---@field declaredType Type|nil
local PTuple = setmetatable({}, { __index = Pattern })
PTuple.__index = PTuple

---@param location Location
---@param items Pattern[]
---@return PTuple
function PTuple.new(location, items)
    return setmetatable({
        kind = "PTuple",
        location = location,
        items = items or {},
    }, PTuple)
end

---@param f fun(stmt: Statement)
function PTuple:iterate(f)
    f(self)
    for _, item in ipairs(self.items) do
        item:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@return nil
---@return string
function PTuple:normalize()
    return nil, "TODO: normalize"
end

return { PTuple = PTuple }
