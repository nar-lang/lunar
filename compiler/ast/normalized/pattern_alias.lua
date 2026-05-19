local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPAlias : NormPattern
---@field kind "NPAlias"
---@field location Location
---@field declaredType NormType|nil
---@field alias Identifier
---@field nested NormPattern
local NPAlias = setmetatable({}, { __index = NormPattern })
NPAlias.__index = NPAlias

---@param location Location
---@param declaredType NormType|nil
---@param alias Identifier
---@param nested NormPattern
---@return NPAlias
function NPAlias.new(location, declaredType, alias, nested)
    return setmetatable({
        kind = "NPAlias",
        location = location,
        declaredType = declaredType,
        alias = alias,
        nested = nested,
    }, NPAlias)
end

---@param f fun(stmt: NormStatement)
function NPAlias:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
end

---@param locals NormPatternMap
function NPAlias:extractLocals(locals)
    locals[self.alias] = self
    if self.nested ~= nil then
        self.nested:extractLocals(locals)
    end
end

return { NPAlias = NPAlias }
