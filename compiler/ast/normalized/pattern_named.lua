local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPNamed : NormPattern
---@field kind "NPNamed"
---@field location Location
---@field declaredType NormType|nil
---@field name Identifier
local NPNamed = setmetatable({}, { __index = NormPattern })
NPNamed.__index = NPNamed

---@param location Location
---@param declaredType NormType|nil
---@param name Identifier
---@return NPNamed
function NPNamed.new(location, declaredType, name)
    return setmetatable({
        kind = "NPNamed",
        location = location,
        declaredType = declaredType,
        name = name,
    }, NPNamed)
end

---@param f fun(stmt: NormStatement)
function NPNamed:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@param locals NormPatternMap
function NPNamed:extractLocals(locals)
    locals[self.name] = self
end

return { NPNamed = NPNamed }
