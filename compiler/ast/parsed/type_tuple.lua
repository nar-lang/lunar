local Type = require("compiler.ast.parsed.type").Type

---@class TTuple : Type
---@field kind "TTuple"
---@field location Location
---@field items Type[]
local TTuple = setmetatable({}, { __index = Type })
TTuple.__index = TTuple

---@param location Location
---@param items Type[]
---@return TTuple
function TTuple.new(location, items)
    return setmetatable({
        kind = "TTuple",
        location = location,
        items = items or {},
    }, TTuple)
end

---@param f fun(stmt: Statement)
function TTuple:iterate(f)
    f(self)
    for _, item in ipairs(self.items) do
        item:iterate(f)
    end
end

---@return nil
---@return string
function TTuple:normalize()
    return nil, "TODO: normalize"
end

return { TTuple = TTuple }
