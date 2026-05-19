local Expression = require("compiler.ast.parsed.expression").Expression

---@class Lambda : Expression
---@field kind "Lambda"
---@field location Location
---@field params Pattern[]
---@field returnType Type|nil
---@field body Expression
local Lambda = setmetatable({}, { __index = Expression })
Lambda.__index = Lambda

---@param location Location
---@param params Pattern[]
---@param returnType Type|nil
---@param body Expression
---@return Lambda
function Lambda.new(location, params, returnType, body)
    return setmetatable({
        kind = "Lambda",
        location = location,
        params = params or {},
        returnType = returnType,
        body = body,
    }, Lambda)
end

---@param f fun(stmt: Statement)
function Lambda:iterate(f)
    f(self)
    for _, p in ipairs(self.params) do
        p:iterate(f)
    end
    if self.returnType ~= nil then
        self.returnType:iterate(f)
    end
    if self.body ~= nil then
        self.body:iterate(f)
    end
end

---@return nil
---@return string
function Lambda:normalize()
    return nil, "TODO: normalize"
end

return { Lambda = Lambda }
