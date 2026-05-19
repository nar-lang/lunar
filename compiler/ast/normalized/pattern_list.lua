local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPList : NormPattern
---@field kind "NPList"
---@field location Location
---@field declaredType NormType|nil
---@field items NormPattern[]
local NPList = setmetatable({}, { __index = NormPattern })
NPList.__index = NPList

---@param location Location
---@param declaredType NormType|nil
---@param items NormPattern[]
---@return NPList
function NPList.new(location, declaredType, items)
    return setmetatable({
        kind = "NPList",
        location = location,
        declaredType = declaredType,
        items = items or {},
    }, NPList)
end

---@param f fun(stmt: NormStatement)
function NPList:iterate(f)
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
function NPList:extractLocals(locals)
    for _, it in ipairs(self.items) do
        if it ~= nil then
            it:extractLocals(locals)
        end
    end
end

return { NPList = NPList }
