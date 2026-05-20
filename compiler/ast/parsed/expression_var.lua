local Expression = require("lunar.compiler.ast.parsed.expression").Expression
local NLocal = require("lunar.compiler.ast.normalized.expression_local").NLocal
local NGlobal = require("lunar.compiler.ast.normalized.expression_global").NGlobal
local Location = require("lunar.compiler.ast.location").Location
local utils = require("lunar.compiler.ast.parsed.utils")
local Access = require("lunar.compiler.ast.parsed.expression_access").Access

---@class Var : Expression
---@field kind "Var"
---@field location Location
---@field name QualifiedIdentifier
local Var = setmetatable({}, { __index = Expression })
Var.__index = Var

---@param location Location
---@param name QualifiedIdentifier
---@return Var
function Var.new(location, name)
    return setmetatable({
        kind = "Var",
        location = location,
        name = name,
    }, Var)
end

---@param f fun(stmt: Statement)
function Var:iterate(f)
    f(self)
end

---@param locals table<Identifier, NormPattern>
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param normalizedModule NormModule
---@return NormExpression|nil
---@return string|nil error
function Var:normalize(locals, modules, module, normalizedModule)
    local lc = locals[self.name]
    if lc ~= nil then
        return self:setSuccessor(NLocal.new(self.location, self.name, lc, self)), nil
    end
    local d, m, ids = module:findDefinitionAndAddDependency(modules, self.name, normalizedModule)
    if ids ~= nil and #ids == 1 then
        ---@cast d Definition
        ---@cast m Module
        return self:setSuccessor(NGlobal.new(self.location, m.name, d.name)), nil
    elseif ids ~= nil and #ids > 1 then
        return nil, utils.newAmbiguousDefinitionError(ids, self.name, self.location)
    end
    -- Try dotted access fallback: "a.b.c" → Access(Access(Var(a), b), c)
    local parts = {}
    for p in string.gmatch(self.name, "[^.]+") do
        parts[#parts + 1] = p
    end
    if #parts > 1 then
        ---@type Expression
        local varAccess = Var.new(self.location, parts[1])
        for i = 2, #parts do
            local namelc = Location.new(
                self.location.filePath,
                self.location.fileContent,
                self.location.start + #parts[1] + 1,
                self.location.finish)
            varAccess = Access.new(self.location, varAccess, parts[i], namelc)
        end
        local access, err = varAccess:normalize(locals, modules, module, normalizedModule)
        if access == nil then
            return nil, err
        end
        return self:setSuccessor(access), nil
    end
    return nil, string.format("identifier `%s` not found", self.name)
end

return { Var = Var }
