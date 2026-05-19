local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPCons : NormPattern
---@field kind "NPCons"
---@field location Location
---@field declaredType NormType|nil
---@field head NormPattern
---@field tail NormPattern
local NPCons = setmetatable({}, { __index = NormPattern })
NPCons.__index = NPCons

---@param location Location
---@param declaredType NormType|nil
---@param head NormPattern
---@param tail NormPattern
---@return NPCons
function NPCons.new(location, declaredType, head, tail)
    return setmetatable({
        kind = "NPCons",
        location = location,
        declaredType = declaredType,
        head = head,
        tail = tail,
    }, NPCons)
end

---@param f fun(stmt: NormStatement)
function NPCons:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    if self.head ~= nil then
        self.head:iterate(f)
    end
    if self.tail ~= nil then
        self.tail:iterate(f)
    end
end

---@param locals NormPatternMap
function NPCons:extractLocals(locals)
    if self.head ~= nil then
        self.head:extractLocals(locals)
    end
    if self.tail ~= nil then
        self.tail:extractLocals(locals)
    end
end

return { NPCons = NPCons }
