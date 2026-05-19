local NormType = require("compiler.ast.normalized.type").NormType
local TNative = require("compiler.ast.typed.type_native").TNative
local NarBaseBasicsUnit = require("compiler.common.builtins").NarBaseBasicsUnit

---@class NTUnit : NormType
---@field kind "NTUnit"
---@field location Location
local NTUnit = setmetatable({}, { __index = NormType })
NTUnit.__index = NTUnit

---@param location Location
---@return NTUnit
function NTUnit.new(location)
    return setmetatable({
        kind = "NTUnit",
        location = location,
    }, NTUnit)
end

---@param f fun(stmt: NormStatement)
function NTUnit:iterate(f)
    f(self)
end

---@param ctx SolvingContext
---@param params TypeParamsMap
---@param source boolean
---@param placeholders PlaceholderMap|nil
---@return TypedType|nil t
---@return string|nil err
function NTUnit:annotate(ctx, params, source, placeholders)
    return self:setSuccessor(TNative.new(self.location, NarBaseBasicsUnit, nil))
end

return { NTUnit = NTUnit }
