local NormPattern = require("compiler.ast.normalized.pattern").NormPattern

---@class NPOption : NormPattern
---@field kind "NPOption"
---@field location Location
---@field declaredType NormType|nil
---@field moduleName QualifiedIdentifier
---@field definitionName Identifier
---@field values NormPattern[]
local NPOption = setmetatable({}, { __index = NormPattern })
NPOption.__index = NPOption

---@param location Location
---@param declaredType NormType|nil
---@param moduleName QualifiedIdentifier
---@param definitionName Identifier
---@param values NormPattern[]
---@return NPOption
function NPOption.new(location, declaredType, moduleName, definitionName, values)
    return setmetatable({
        kind = "NPOption",
        location = location,
        declaredType = declaredType,
        moduleName = moduleName,
        definitionName = definitionName,
        values = values or {},
    }, NPOption)
end

---@param f fun(stmt: NormStatement)
function NPOption:iterate(f)
    f(self)
    if self.declaredType ~= nil then
        self.declaredType:iterate(f)
    end
    for _, v in ipairs(self.values) do
        if v ~= nil then
            v:iterate(f)
        end
    end
end

---@param locals NormPatternMap
function NPOption:extractLocals(locals)
    for _, v in ipairs(self.values) do
        if v ~= nil then
            v:extractLocals(locals)
        end
    end
end

return { NPOption = NPOption }
