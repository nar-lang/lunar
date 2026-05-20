local NormType = require("lunar.compiler.ast.normalized.type").NormType
local TyFunc = require("lunar.compiler.ast.typed.type_func").TyFunc

---@class NTFunc : NormType
---@field kind "NTFunc"
---@field location Location
---@field params NormType[]
---@field return_ NormType
local NTFunc = setmetatable({}, { __index = NormType })
NTFunc.__index = NTFunc

---@param location Location
---@param params NormType[]
---@param ret NormType
---@return NTFunc
function NTFunc.new(location, params, ret)
    return setmetatable({
        kind = "NTFunc",
        location = location,
        params = params or {},
        return_ = ret,
    }, NTFunc)
end

---@param f fun(stmt: NormStatement)
function NTFunc:iterate(f)
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

---@param ctx SolvingContext
---@param params TypeParamsMap
---@param source boolean
---@param placeholders PlaceholderMap|nil
---@return TypedType|nil t
---@return string|nil err
function NTFunc:annotate(ctx, params, source, placeholders)
    ---@type TypedType[]
    local funcParams = {}
    for i, t in ipairs(self.params) do
        if t == nil then
            return nil, "function parameter type is not declared"
        end
        local x, err = t:annotate(ctx, params, source, placeholders)
        if err ~= nil then
            return nil, err
        end
        ---@cast x -nil
        funcParams[i] = x
    end
    if self.return_ == nil then
        return nil, "function return type is not declared"
    end
    local ret, err = self.return_:annotate(ctx, params, source, placeholders)
    if err ~= nil then
        return nil, err
    end
    ---@cast ret -nil
    return self:setSuccessor(TyFunc.new(self.location, funcParams, ret))
end

return { NTFunc = NTFunc }
