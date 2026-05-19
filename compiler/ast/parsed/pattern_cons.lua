local Pattern = require("compiler.ast.parsed.pattern").Pattern

---@class PCons : Pattern
---@field kind "PCons"
---@field location Location
---@field head Pattern
---@field tail Pattern
---@field declaredType Type|nil
local PCons = setmetatable({}, { __index = Pattern })
PCons.__index = PCons

---@param location Location
---@param head Pattern
---@param tail Pattern
---@return PCons
function PCons.new(location, head, tail)
    return setmetatable({
        kind = "PCons",
        location = location,
        head = head,
        tail = tail,
    }, PCons)
end

---@param f fun(stmt: Statement)
function PCons:iterate(f)
    f(self)
    if self.head ~= nil then
        self.head:iterate(f)
    end
    if self.tail ~= nil then
        self.tail:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@return nil
---@return string
function PCons:normalize()
    return nil, "TODO: normalize"
end

return { PCons = PCons }
