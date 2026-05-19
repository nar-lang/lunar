local Expression = require("compiler.ast.parsed.expression").Expression

---@class Call : Expression
---@field kind "Call"
---@field location Location
---@field name FullIdentifier
---@field args Expression[]
local Call = setmetatable({}, { __index = Expression })
Call.__index = Call

---@param location Location
---@param name FullIdentifier
---@param args Expression[]
---@return Call
function Call.new(location, name, args)
    return setmetatable({
        kind = "Call",
        location = location,
        name = name,
        args = args or {},
    }, Call)
end

---@param f fun(stmt: Statement)
function Call:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
end

---@return nil
---@return string
function Call:normalize()
    return nil, "TODO: normalize"
end

return { Call = Call }
