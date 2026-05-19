local Pattern = require("compiler.ast.parsed.pattern").Pattern

---@class PList : Pattern
---@field kind "PList"
---@field location Location
---@field items Pattern[]
---@field declaredType Type|nil
local PList = setmetatable({}, { __index = Pattern })
PList.__index = PList

---@param location Location
---@param items Pattern[]
---@return PList
function PList.new(location, items)
    return setmetatable({
        kind = "PList",
        location = location,
        items = items or {},
    }, PList)
end

---@param f fun(stmt: Statement)
function PList:iterate(f)
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
function PList:normalize()
    return nil, "TODO: normalize"
end

return { PList = PList }
