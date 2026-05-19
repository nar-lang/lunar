local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPAny : NormPattern
---@field kind "NPAny"
---@field location Location
---@field declaredType NormType|nil
local NPAny = setmetatable({}, { __index = NormPattern })
NPAny.__index = NPAny

---@param location Location
---@param declaredType NormType|nil
---@return NPAny
function NPAny.new(location, declaredType)
    return setmetatable({
        kind = "NPAny",
        location = location,
        declaredType = declaredType,
    }, NPAny)
end

---@param f fun(stmt: NormStatement)
function NPAny:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals NormPatternMap
function NPAny:extractLocals(locals)
end

return { NPAny = NPAny }
