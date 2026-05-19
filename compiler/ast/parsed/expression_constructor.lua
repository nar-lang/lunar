local Expression = require("compiler.ast.parsed.expression").Expression

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

---@return nil
---@return string
function Constructor:normalize()
    return nil, "TODO: normalize"
end

return { Constructor = Constructor }
