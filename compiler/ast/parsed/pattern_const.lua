local Pattern = require("compiler.ast.parsed.pattern").Pattern

---@class PConst : Pattern
---@field kind "PConst"
---@field location Location
---@field value ConstValue
---@field declaredType Type|nil
local PConst = setmetatable({}, { __index = Pattern })
PConst.__index = PConst

---@param location Location
---@param value ConstValue
---@return PConst
function PConst.new(location, value)
    return setmetatable({
        kind = "PConst",
        location = location,
        value = value,
    }, PConst)
end

---@param f fun(stmt: Statement)
function PConst:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@return nil
---@return string
function PConst:normalize()
    return nil, "TODO: normalize"
end

return { PConst = PConst }
