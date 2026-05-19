local Type = require("compiler.ast.parsed.type").Type

---@class TNamed : Type
---@field kind "TNamed"
---@field location Location
---@field name QualifiedIdentifier
---@field args Type[]
---@field nameLocation Location
local TNamed = setmetatable({}, { __index = Type })
TNamed.__index = TNamed

---@param location Location
---@param name QualifiedIdentifier
---@param args Type[]
---@param nameLocation Location
---@return TNamed
function TNamed.new(location, name, args, nameLocation)
    return setmetatable({
        kind = "TNamed",
        location = location,
        name = name,
        args = args or {},
        nameLocation = nameLocation,
    }, TNamed)
end

---@param f fun(stmt: Statement)
function TNamed:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
end

---@return nil
---@return string
function TNamed:normalize()
    return nil, "TODO: normalize"
end

return { TNamed = TNamed }
