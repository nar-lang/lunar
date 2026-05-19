---@class BinOpItem
---@field operand Expression|nil
---@field infix InfixIdentifier|nil
---@field fn Infix|nil
local BinOpItem = {}
BinOpItem.__index = BinOpItem

---@param expression Expression
---@return BinOpItem
function BinOpItem.newOperand(expression)
    return setmetatable({ operand = expression }, BinOpItem)
end

---@param infix InfixIdentifier
---@return BinOpItem
function BinOpItem.newFunc(infix)
    return setmetatable({ infix = infix }, BinOpItem)
end

local Expression = require("compiler.ast.parsed.expression").Expression

---@class BinOp : Expression
---@field kind "BinOp"
---@field location Location
---@field items BinOpItem[]
---@field inParentheses boolean
local BinOp = setmetatable({}, { __index = Expression })
BinOp.__index = BinOp

---@param location Location
---@param items BinOpItem[]
---@param inParentheses boolean
---@return BinOp
function BinOp.new(location, items, inParentheses)
    return setmetatable({
        kind = "BinOp",
        location = location,
        items = items or {},
        inParentheses = inParentheses == true,
    }, BinOp)
end

---@param value boolean
function BinOp:setInParentheses(value)
    self.inParentheses = value
end

---@return boolean
function BinOp:getInParentheses()
    return self.inParentheses
end

---@return BinOpItem[]
function BinOp:getItems()
    return self.items
end

---@param f fun(stmt: Statement)
function BinOp:iterate(f)
    f(self)
    for _, item in ipairs(self.items) do
        if item.operand ~= nil then
            item.operand:iterate(f)
        end
    end
end

---@return nil
---@return string
function BinOp:normalize()
    return nil, "TODO: normalize"
end

return { BinOp = BinOp, BinOpItem = BinOpItem }
