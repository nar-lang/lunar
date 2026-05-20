local TypedType = require("compiler.ast.typed.type").TypedType
local newEquationBestLoc = require("compiler.ast.typed.equation").newEquationBestLoc

---@class TyRecordType : TypedType
---@field kind "TRecord"
---@field location Location
---@field fields table<Identifier, TypedType>
---@field mayHaveMoreFields boolean
local TyRecordType = setmetatable({}, { __index = TypedType })
TyRecordType.__index = TyRecordType

---@param loc Location
---@param fields table<Identifier, TypedType>|nil
---@param mayHaveMoreFields boolean
---@return TyRecordType
function TyRecordType.new(loc, fields, mayHaveMoreFields)
    return setmetatable({
        kind = "TRecord",
        location = loc,
        fields = fields or {},
        mayHaveMoreFields = mayHaveMoreFields == true,
    }, TyRecordType)
end

---@param ctx SolvingContext
---@param ubMap table<integer, integer>
---@return TyRecordType
function TyRecordType:makeUnique(ctx, ubMap)
    ---@type table<Identifier, TypedType>
    local nf = {}
    for n, f in pairs(self.fields) do
        nf[n] = f:makeUnique(ctx, ubMap)
    end
    return TyRecordType.new(self.location, nf, self.mayHaveMoreFields)
end

---@param other TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TyRecordType:merge(other, loc)
    if other == nil or other.kind ~= "TRecord" then
        local otherCode = other ~= nil and other:code("") or "nil"
        return nil, string.format("cannot match %s and %s", otherCode, self:code(""))
    end
    ---@cast other TyRecordType
    ---@type Equation[]
    local eqs = {}
    -- Iterate in sorted order for deterministic equation list ordering.
    local lkeys = {}
    for n in pairs(self.fields) do
        lkeys[#lkeys + 1] = n
    end
    table.sort(lkeys)
    for _, n in ipairs(lkeys) do
        local f = self.fields[n]
        local of = other.fields[n]
        if of ~= nil then
            eqs[#eqs + 1] = newEquationBestLoc(f, of, loc)
        elseif not other.mayHaveMoreFields then
            return nil, string.format("record missing field `%s`", n)
        end
    end
    local rkeys = {}
    for n in pairs(other.fields) do
        rkeys[#rkeys + 1] = n
    end
    table.sort(rkeys)
    for _, n in ipairs(rkeys) do
        if self.fields[n] == nil and not self.mayHaveMoreFields then
            return nil, string.format("record missing field `%s`", n)
        end
    end
    return eqs, nil
end

---@param subst table<integer, TypedType>
---@return TypedType|nil t
---@return string|nil err
function TyRecordType:mapTo(subst)
    for n, f in pairs(self.fields) do
        local x, err = f:mapTo(subst)
        if err ~= nil then
            return nil, err
        end
        ---@cast x -nil
        self.fields[n] = x
    end
    return self, nil
end

---@param other TypedType
---@param req table<FullIdentifier, true>|nil
---@return boolean
function TyRecordType:equalsTo(other, req)
    if other == nil or other.kind ~= "TRecord" then
        return false
    end
    ---@cast other TyRecordType
    local lc = 0
    for _ in pairs(self.fields) do
        lc = lc + 1
    end
    local rc = 0
    for _ in pairs(other.fields) do
        rc = rc + 1
    end
    if lc ~= rc then
        return false
    end
    for n, fx in pairs(self.fields) do
        local fy = other.fields[n]
        if fy == nil then
            return false
        end
        if not fx:equalsTo(fy, req) then
            return false
        end
    end
    return true
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyRecordType:code(currentModule)
    -- Sort fields for deterministic output (mirrors Go map iteration via
    -- the Lua port's stable rendering policy).
    local keys = {}
    for n in pairs(self.fields) do
        keys[#keys + 1] = n
    end
    table.sort(keys)
    local parts = {}
    for _, n in ipairs(keys) do
        parts[#parts + 1] = string.format("%s:%s", n, self.fields[n]:code(""))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

return { TyRecordType = TyRecordType }
