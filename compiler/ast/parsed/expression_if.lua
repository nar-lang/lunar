local Expression = require("compiler.ast.parsed.expression").Expression
local NSelect = require("compiler.ast.normalized.expression_select").NSelect
local NSelectCase = require("compiler.ast.normalized.expression_select").NSelectCase
local NTData = require("compiler.ast.normalized.type_data").NTData
local NDataOption = require("compiler.ast.normalized.type_data").NDataOption
local NPOption = require("compiler.ast.normalized.pattern_option").NPOption
local builtins = require("compiler.common.builtins")

---@class If : Expression
---@field kind "If"
---@field location Location
---@field condition Expression
---@field positive Expression
---@field negative Expression
local If = setmetatable({}, { __index = Expression })
If.__index = If

---@param location Location
---@param condition Expression
---@param positive Expression
---@param negative Expression
---@return If
function If.new(location, condition, positive, negative)
    return setmetatable({
        kind = "If",
        location = location,
        condition = condition,
        positive = positive,
        negative = negative,
    }, If)
end

---@param f fun(stmt: Statement)
function If:iterate(f)
    f(self)
    if self.condition ~= nil then
        self.condition:iterate(f)
    end
    if self.positive ~= nil then
        self.positive:iterate(f)
    end
    if self.negative ~= nil then
        self.negative:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function If:normalize(locals, modules, module, normalizedModule)
    local boolType = NTData.new(
        self.condition.location,
        builtins.NarBaseBasicsBool,
        {},
        {
            NDataOption.new(builtins.NarTrueName, false, {}),
            NDataOption.new(builtins.NarFalseName, false, {}),
        })
    local condition, err = self.condition:normalize(locals, modules, module, normalizedModule)
    if condition == nil then
        return nil, err
    end
    local positive, err2 = self.positive:normalize(locals, modules, module, normalizedModule)
    if positive == nil then
        return nil, err2
    end
    local negative, err3 = self.negative:normalize(locals, modules, module, normalizedModule)
    if negative == nil then
        return nil, err3
    end
    return self:setSuccessor(NSelect.new(self.location, condition, {
        NSelectCase.new(self.positive.location,
            NPOption.new(self.positive.location, boolType,
                builtins.NarBaseBasicsName, builtins.NarTrueName, {}),
            positive),
        NSelectCase.new(self.negative.location,
            NPOption.new(self.negative.location, boolType,
                builtins.NarBaseBasicsName, builtins.NarFalseName, {}),
            negative),
    })), nil
end

return { If = If }
