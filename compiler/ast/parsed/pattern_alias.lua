local Pattern = require("compiler.ast.parsed.pattern").Pattern

---@class PAlias : Pattern
---@field kind "PAlias"
---@field location Location
---@field alias Identifier
---@field nested Pattern
---@field declaredType Type|nil
local PAlias = setmetatable({}, { __index = Pattern })
PAlias.__index = PAlias

---@param location Location
---@param alias Identifier
---@param nested Pattern
---@return PAlias
function PAlias.new(location, alias, nested)
    return setmetatable({
        kind = "PAlias",
        location = location,
        alias = alias,
        nested = nested,
    }, PAlias)
end

---@param f fun(stmt: Statement)
function PAlias:iterate(f)
    f(self)
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
end

---@return nil
---@return string
function PAlias:normalize()
    return nil, "TODO: normalize"
end

return { PAlias = PAlias }
