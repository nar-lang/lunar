local NormType = require("compiler.ast.normalized.type").NormType

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

return { NTFunc = NTFunc }
