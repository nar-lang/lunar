local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPTuple : NormPattern
---@field kind "NPTuple"
---@field location Location
---@field declaredType NormType|nil
---@field items NormPattern[]
local NPTuple = setmetatable({}, { __index = NormPattern })
NPTuple.__index = NPTuple

---@param location Location
---@param declaredType NormType|nil
---@param items NormPattern[]
---@return NPTuple
function NPTuple.new(location, declaredType, items)
    return setmetatable({
        kind = "NPTuple",
        location = location,
        declaredType = declaredType,
        items = items or {},
    }, NPTuple)
end

---@param f fun(stmt: NormStatement)
function NPTuple:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    for _, it in ipairs(self.items) do
        if it ~= nil then
            it:iterate(f)
        end
    end
end

---@param locals NormPatternMap
function NPTuple:extractLocals(locals)
    for _, it in ipairs(self.items) do
        if it ~= nil then
            it:extractLocals(locals)
        end
    end
end

return { NPTuple = NPTuple }
