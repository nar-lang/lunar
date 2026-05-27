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

local Expression = require("lunar.compiler.ast.parsed.expression").Expression
local NApply = require("lunar.compiler.ast.normalized.expression_apply").NApply
local NGlobal = require("lunar.compiler.ast.normalized.expression_global").NGlobal
local utils = require("lunar.compiler.ast.parsed.utils")

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

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function BinOp:normalize(locals, modules, module, normalizedModule)
    ---@type BinOpItem[]
    local output = {}
    ---@type BinOpItem[]
    local operators = {}
    for _, o1 in ipairs(self.items) do
        if o1.operand ~= nil then
            output[#output + 1] = o1
        else
            ---@type InfixIdentifier|nil
            local o1infixOpt = o1.infix
            if o1infixOpt == nil then
                return nil, "binop item has neither operand nor infix"
            end
            ---@type InfixIdentifier
            local o1infix = o1infixOpt
            local infixFn, _, ids = module:findInfixFn(modules, o1infix)
            if ids == nil or #ids ~= 1 then
                ---@type FullIdentifier[]
                local idList = ids or {}
                return nil, utils.newAmbiguousInfixError(idList, o1infix, self.location)
            end
            ---@cast infixFn Infix
            o1.fn = infixFn
            for i = #operators, 1, -1 do
                ---@type BinOpItem
                local o2 = operators[i]
                ---@type Infix|nil
                local o2fn = o2.fn
                if o2fn ~= nil and infixFn:hasLowerPrecedenceThan(o2fn) then
                    output[#output + 1] = o2
                    operators[#operators] = nil
                else
                    break
                end
            end
            operators[#operators + 1] = o1
        end
    end
    for i = #operators, 1, -1 do
        output[#output + 1] = operators[i]
    end

    ---@return NormExpression|nil, string|nil
    local function buildTree()
        local last = output[#output]
        ---@cast last BinOpItem
        local op = last.infix
        ---@cast op InfixIdentifier
        output[#output] = nil
        local infixA, m, fids = module:findInfixFn(modules, op)
        if fids == nil or #fids ~= 1 then
            return nil, utils.newAmbiguousInfixError(fids or {}, op, self.location)
        end
        ---@cast infixA Infix
        ---@cast m Module
        ---@type NormExpression|nil, NormExpression|nil, string|nil
        local left, right, err
        local r = output[#output]
        ---@cast r BinOpItem
        local rop = r.operand
        if rop ~= nil then
            right, err = rop:normalize(locals, modules, module, normalizedModule)
            if right == nil then
                return nil, err
            end
            output[#output] = nil
        else
            right, err = buildTree()
            if right == nil then
                return nil, err
            end
        end
        local l = output[#output]
        ---@cast l BinOpItem
        local lop = l.operand
        if lop ~= nil then
            left, err = lop:normalize(locals, modules, module, normalizedModule)
            if left == nil then
                return nil, err
            end
            output[#output] = nil
        else
            left, err = buildTree()
            if left == nil then
                return nil, err
            end
        end
        -- Infix operators resolve to a definition in module `m` via
        -- `findInfixFn`. That lookup path bypasses
        -- `findDefinitionAndAddDependency`, so we must register the
        -- dependency explicitly here. Without this, `link` may try to
        -- emit a reference to `m.alias` before module `m` has been
        -- composed (when composing in alphabetical name order), and
        -- the bytecode global lookup fails with
        --   global definition `<m>.<alias>` not found
        normalizedModule:addDependencies(m.name, infixA.alias)
        return NApply.new(
            self.location,
            NGlobal.new(self.location, m.name, infixA.alias),
            { left, right }), nil
    end

    local tree, err = buildTree()
    if tree == nil then
        return nil, err
    end
    return self:setSuccessor(tree), nil
end

return { BinOp = BinOp, BinOpItem = BinOpItem }
