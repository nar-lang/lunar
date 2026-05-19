local Statement = require("compiler.ast.parsed.defines").Statement

---@class Definition : Statement
---@field kind "Definition"
---@field location Location
---@field hidden boolean
---@field name Identifier
---@field nameLocation Location
---@field params Pattern[]
---@field body Expression?
---@field declaredType Type|nil
local Definition = setmetatable({}, { __index = Statement })
Definition.__index = Definition

---@param location Location
---@param hidden boolean
---@param name Identifier
---@param nameLocation Location
---@param params Pattern[]
---@param body Expression?
---@param declaredType Type|nil
---@return Definition
function Definition.new(location, hidden, name, nameLocation, params, body, declaredType)
    return setmetatable({
        kind = "Definition",
        location = location,
        hidden = hidden == true,
        name = name,
        nameLocation = nameLocation,
        params = params or {},
        body = body,
        declaredType = declaredType,
    }, Definition)
end

---@param f fun(stmt: Statement)
function Definition:iterate(f)
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
end

---@return nil
---@return string
function Definition:normalize()
    return nil, "TODO: normalize"
end

return { Definition = Definition }
