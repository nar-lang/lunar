local Expression = require("compiler.ast.parsed.expression").Expression
local NGlobal = require("compiler.ast.normalized.expression_global").NGlobal
local utils = require("compiler.ast.parsed.utils")

---@class InfixVar : Expression
---@field kind "InfixVar"
---@field location Location
---@field infix InfixIdentifier
local InfixVar = setmetatable({}, { __index = Expression })
InfixVar.__index = InfixVar

---@param location Location
---@param infix InfixIdentifier
---@return InfixVar
function InfixVar.new(location, infix)
    return setmetatable({
        kind = "InfixVar",
        location = location,
        infix = infix,
    }, InfixVar)
end

---@param f fun(stmt: Statement)
function InfixVar:iterate(f)
    f(self)
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function InfixVar:normalize(locals, modules, module, normalizedModule)
    local i, infixModule, ids = module:findInfixFn(modules, self.infix)
    if ids == nil or #ids ~= 1 then
        ---@type FullIdentifier[]
        local idList = ids or {}
        return nil, utils.newAmbiguousInfixError(idList, self.infix, self.location)
    end
    ---@cast i Infix
    ---@cast infixModule Module
    local d, m, dids = infixModule:findDefinitionAndAddDependency(nil, i.alias, normalizedModule)
    if dids == nil or #dids ~= 1 then
        ---@type FullIdentifier[]
        local idList = dids or {}
        return nil, utils.newAmbiguousDefinitionError(idList, i.alias, self.location)
    end
    ---@cast d Definition
    ---@cast m Module
    return self:setSuccessor(NGlobal.new(self.location, m.name, d.name)), nil
end

return { InfixVar = InfixVar }
