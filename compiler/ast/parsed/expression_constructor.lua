local Expression = require("compiler.ast.parsed.expression").Expression
local NConstructor = require("compiler.ast.normalized.expression_constructor").NConstructor

---@class Constructor : Expression
---@field kind "Constructor"
---@field location Location
---@field moduleName QualifiedIdentifier
---@field dataName Identifier
---@field optionName Identifier
---@field nameLocation Location
---@field args Expression[]
local Constructor = setmetatable({}, { __index = Expression })
Constructor.__index = Constructor

---@param location Location
---@param moduleName QualifiedIdentifier
---@param dataName Identifier
---@param optionName Identifier
---@param nameLocation Location
---@param args Expression[]
---@return Constructor
function Constructor.new(location, moduleName, dataName, optionName, nameLocation, args)
    return setmetatable({
        kind = "Constructor",
        location = location,
        moduleName = moduleName,
        dataName = dataName,
        optionName = optionName,
        nameLocation = nameLocation,
        args = args or {},
    }, Constructor)
end

---@param f fun(stmt: Statement)
function Constructor:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Constructor:normalize(locals, modules, module, normalizedModule)
    local args = {}
    for i, arg in ipairs(self.args) do
        local nArg, err = arg:normalize(locals, modules, module, normalizedModule)
        if nArg == nil then
            return nil, err
        end
        args[i] = nArg
    end
    return self:setSuccessor(
        NConstructor.new(self.location, self.moduleName, self.dataName, self.optionName, args)), nil
end

return { Constructor = Constructor }
