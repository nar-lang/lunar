local Type = require("compiler.ast.parsed.type").Type
local NTFunc = require("compiler.ast.normalized.type_func").NTFunc

---@class TFunc : Type
---@field kind "TFunc"
---@field location Location
---@field params (Type?)[]
---@field return_ Type?
local TFunc = setmetatable({}, { __index = Type })
TFunc.__index = TFunc

---@param location Location
---@param params (Type?)[]
---@param ret Type?
---@return TFunc?
function TFunc.new(location, params, ret)
    if ret == nil then
        local hasParam = false
        if params ~= nil then
            for _, p in ipairs(params) do
                if p ~= nil then
                    hasParam = true
                    break
                end
            end
        end
        if not hasParam then
            return nil
        end
    end
    return setmetatable({
        kind = "TFunc",
        location = location,
        params = params or {},
        return_ = ret,
    }, TFunc)
end

---@param f fun(stmt: Statement)
function TFunc:iterate(f)
    f(self)
    for _, p in ipairs(self.params) do
        if p ~= nil then
            p:iterate(f)
        end
    end
    if self.return_ ~= nil then
        self.return_:iterate(f)
    end
end

---@param modules table<QualifiedIdentifier, Module>
---@param module Module
---@param namedTypes NamedTypeMap|nil
---@return NormType|nil
---@return string|nil error
function TFunc:normalize(modules, module, namedTypes)
    local params = {}
    for i, p in ipairs(self.params) do
        if p == nil then
            return nil, "missing parameter type annotation"
        end
        local np, err = p:normalize(modules, module, namedTypes)
        if err ~= nil then
            return nil, err
        end
        params[i] = np
    end
    if self.return_ == nil then
        return nil, "missing return type annotation"
    end
    local ret, err = self.return_:normalize(modules, module, namedTypes)
    if err ~= nil or ret == nil then
        return nil, err or "failed to normalize return type"
    end
    return self:setSuccessor(NTFunc.new(self.location, params, ret)), nil
end

---@param params table<Identifier, Type>
---@param loc Location
---@return Type|nil
---@return string|nil error
function TFunc:applyArgs(params, loc)
    local fnParams = {}
    for i, p in ipairs(self.params) do
        if p == nil then
            return nil, "missing parameter type annotation"
        end
        local np, err = p:applyArgs(params, loc)
        if err ~= nil then
            return nil, err
        end
        fnParams[i] = np
    end
    if self.return_ == nil then
        return nil, "missing return type annotation"
    end
    local ret, err = self.return_:applyArgs(params, loc)
    if err ~= nil then
        return nil, err
    end
    return TFunc.new(loc, fnParams, ret), nil
end

return { TFunc = TFunc }
