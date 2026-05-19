local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPConst : NormPattern
---@field kind "NPConst"
---@field location Location
---@field declaredType NormType|nil
---@field value ConstValue
local NPConst = setmetatable({}, { __index = NormPattern })
NPConst.__index = NPConst

---@param location Location
---@param declaredType NormType|nil
---@param value ConstValue
---@return NPConst
function NPConst.new(location, declaredType, value)
    return setmetatable({
        kind = "NPConst",
        location = location,
        declaredType = declaredType,
        value = value,
    }, NPConst)
end

---@param f fun(stmt: NormStatement)
function NPConst:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals NormPatternMap
function NPConst:extractLocals(locals)
end

return { NPConst = NPConst }
