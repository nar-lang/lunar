---Simplified pattern representation used by the exhaustiveness checker.

---@class SimplePattern
---@field kind string
local SimplePattern = {}
SimplePattern.__index = SimplePattern

---@class SimpleAnything : SimplePattern
---@field kind "SimpleAnything"
local SimpleAnything = setmetatable({}, { __index = SimplePattern })
SimpleAnything.__index = SimpleAnything

---@return SimpleAnything
function SimpleAnything.new()
    return setmetatable({ kind = "SimpleAnything" }, SimpleAnything)
end

---@return string
function SimpleAnything:toString()
    return "_"
end

---@class SimpleLiteral : SimplePattern
---@field kind "SimpleLiteral"
---@field literal ConstValue
local SimpleLiteral = setmetatable({}, { __index = SimplePattern })
SimpleLiteral.__index = SimpleLiteral

---@param literal ConstValue
---@return SimpleLiteral
function SimpleLiteral.new(literal)
    return setmetatable({
        kind = "SimpleLiteral",
        literal = literal,
    }, SimpleLiteral)
end

---@param v ConstValue
---@return string
local function constCode(v)
    local k = v.kind
    if k == "CInt" then
        return string.format("%d", v.value)
    elseif k == "CFloat" then
        return string.format("%f", v.value)
    elseif k == "CString" then
        return string.format('"%s"', v.value)
    elseif k == "CChar" then
        return string.format("'%s'", v.value)
    elseif k == "CUnit" then
        return "()"
    end
    return tostring(k)
end

---@return string
function SimpleLiteral:toString()
    return constCode(self.literal)
end

---@class SimpleConstructor : SimplePattern
---@field kind "SimpleConstructor"
---@field union TData
---@field name DataOptionIdentifier
---@field args SimplePattern[]
local SimpleConstructor = setmetatable({}, { __index = SimplePattern })
SimpleConstructor.__index = SimpleConstructor

---@param union TData
---@param name DataOptionIdentifier
---@param args SimplePattern[]
---@return SimpleConstructor
function SimpleConstructor.new(union, name, args)
    return setmetatable({
        kind = "SimpleConstructor",
        union = union,
        name = name,
        args = args or {},
    }, SimpleConstructor)
end

---@return string
function SimpleConstructor:toString()
    local parts = { tostring(self.name) }
    if #self.args > 0 then
        parts[#parts + 1] = "("
        for i, a in ipairs(self.args) do
            if i > 1 then
                parts[#parts + 1] = ", "
            end
            parts[#parts + 1] = a:toString()
        end
        parts[#parts + 1] = ")"
    end
    return table.concat(parts)
end

---@return DataOption|nil
---@return string|nil err
function SimpleConstructor:option()
    for _, o in ipairs(self.union.options) do
        if o.name == self.name then
            return o, nil
        end
    end
    return nil, "option not found"
end

return {
    SimplePattern = SimplePattern,
    SimpleAnything = SimpleAnything,
    SimpleLiteral = SimpleLiteral,
    SimpleConstructor = SimpleConstructor,
}
