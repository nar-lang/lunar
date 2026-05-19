local Expression = require("compiler.ast.parsed.expression").Expression

---@class Function : Expression
---@field kind "Function"
---@field location Location
---@field name Identifier
---@field nameLocation Location
---@field params Pattern[]
---@field body Expression
---@field declaredType Type|nil
---@field nested Expression
local Function = setmetatable({}, { __index = Expression })
Function.__index = Function

---@param location Location
---@param name Identifier
---@param nameLocation Location
---@param params Pattern[]
---@param body Expression
---@param declaredType Type|nil
---@param nested Expression
---@return Function
function Function.new(location, name, nameLocation, params, body, declaredType, nested)
    return setmetatable({
        kind = "Function",
        location = location,
        name = name,
        nameLocation = nameLocation,
        params = params or {},
        body = body,
        declaredType = declaredType,
        nested = nested,
    }, Function)
end

---@param f fun(stmt: Statement)
function Function:iterate(f)
    f(self)
    for _, p in ipairs(self.params) do
        p:iterate(f)
    end
    if self.body ~= nil then
        self.body:iterate(f)
    end
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    if self.nested ~= nil then
        self.nested:iterate(f)
    end
end

---@return nil
---@return string
function Function:normalize()
    return nil, "TODO: normalize"
end

return { Function = Function }
