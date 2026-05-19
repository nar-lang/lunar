local Expression = require("compiler.ast.parsed.expression").Expression

---@class Apply : Expression
---@field kind "Apply"
---@field location Location
---@field func Expression
---@field args Expression[]
local Apply = setmetatable({}, { __index = Expression })
Apply.__index = Apply

---@param location Location
---@param func Expression
---@param args Expression[]
---@return Apply
function Apply.new(location, func, args)
    return setmetatable({
        kind = "Apply",
        location = location,
        func = func,
        args = args or {},
    }, Apply)
end

---@param f fun(stmt: Statement)
function Apply:iterate(f)
    f(self)
    if self.func ~= nil then
        self.func:iterate(f)
    end
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
end

---@return nil
---@return string
function Apply:normalize()
    return nil, "TODO: normalize"
end

return { Apply = Apply }
