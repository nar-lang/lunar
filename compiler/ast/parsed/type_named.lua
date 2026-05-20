local Type = require("compiler.ast.parsed.type").Type

---@class TNamed : Type
---@field kind "TNamed"
---@field location Location
---@field name QualifiedIdentifier
---@field args Type[]
---@field nameLocation Location
local TNamed = setmetatable({}, { __index = Type })
TNamed.__index = TNamed

---@param location Location
---@param name QualifiedIdentifier
---@param args Type[]
---@param nameLocation Location
---@return TNamed
function TNamed.new(location, name, args, nameLocation)
    return setmetatable({
        kind = "TNamed",
        location = location,
        name = name,
        args = args or {},
        nameLocation = nameLocation,
    }, TNamed)
end

---@param f fun(stmt: Statement)
function TNamed:iterate(f)
    f(self)
    for _, a in ipairs(self.args) do
        a:iterate(f)
    end
end

---Resolve this named-type reference through the module's imports.
---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@return Type|nil
---@return Module|nil
---@return FullIdentifier[]|nil
---@return string|nil error
function TNamed:find(modules, module)
    return module:findType(modules, self.name, self.args, self.location)
end

---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param namedTypes NamedTypeMap|nil
---@return NormType|nil
---@return string|nil error
function TNamed:normalize(modules, module, namedTypes)
    local x, _, ids, err = self:find(modules, module)
    if err ~= nil then
        return nil, err
    end
    if ids == nil then
        local args = ""
        if #self.args > 0 then
            local parts = {}
            for i = 1, #self.args do
                parts[i] = "_"
            end
            args = string.format("[%s]", table.concat(parts, ", "))
        end
        return nil, string.format("type `%s%s` not found", self.name, args)
    end
    if #ids > 1 then
        return nil, string.format(
            "ambiguous type `%s`, it can be one of %s. " ..
            "Use import or qualified Name to clarify which one to use",
            self.name, table.concat(ids, ", "))
    end
    if x == nil then
        return nil, string.format("type `%s` not found", self.name)
    end
    if getmetatable(x) == TNamed then
        ---@cast x TNamed
        if x.name == self.name then
            return nil, string.format("type `%s` aliased to itself", self.name)
        end
    end
    local nType, err2 = x:normalize(modules, module, namedTypes)
    if err2 ~= nil then
        return nil, err2
    end
    ---@cast nType -nil
    return self:setSuccessor(nType), nil
end

---@param params table<Identifier, Type>
---@param loc Location
---@return Type|nil
---@return string|nil error
function TNamed:applyArgs(params, loc)
    local args = {}
    for i, a in ipairs(self.args) do
        local na, err = a:applyArgs(params, loc)
        if err ~= nil then
            return nil, err
        end
        ---@cast na -nil
        args[i] = na
    end
    return TNamed.new(loc, self.name, args, self.nameLocation), nil
end

return { TNamed = TNamed }
