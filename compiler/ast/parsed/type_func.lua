local Type = require("compiler.ast.parsed.type").Type

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
---@return TFunc
function TFunc.new(location, params, ret)
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

---@return nil
---@return string
function TFunc:normalize()
    return nil, "TODO: normalize"
end

return { TFunc = TFunc }
