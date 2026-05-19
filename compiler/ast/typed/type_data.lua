local TypedType = require("compiler.ast.typed.type").TypedType
local newEquationBestLoc = require("compiler.ast.typed.equation").newEquationBestLoc

---@class DataOption
---@field name DataOptionIdentifier
---@field values TypedType[]
local DataOption = {}
DataOption.__index = DataOption

---@param name DataOptionIdentifier
---@param values TypedType[]|nil
---@return DataOption
function DataOption.new(name, values)
    return setmetatable({
        name = name,
        values = values or {},
    }, DataOption)
end

---@class TData : TypedType
---@field kind "TData"
---@field location Location
---@field name FullIdentifier
---@field args TypedType[]
---@field options DataOption[]
local TData = setmetatable({}, { __index = TypedType })
TData.__index = TData

---@param loc Location
---@param name FullIdentifier
---@param args TypedType[]|nil
---@param options DataOption[]|nil
---@return TData
function TData.new(loc, name, args, options)
    return setmetatable({
        kind = "TData",
        location = loc,
        name = name,
        args = args or {},
        options = options or {},
    }, TData)
end

---@param options DataOption[]
function TData:setOptions(options)
    self.options = options or {}
end

---@param ctx SolvingContext
---@param ubMap table<integer, integer>
---@return TData
function TData:makeUnique(ctx, ubMap)
    ---@type TypedType[]
    local args = {}
    for i, a in ipairs(self.args) do
        args[i] = a:makeUnique(ctx, ubMap)
    end
    return TData.new(self.location, self.name, args, self.options)
end

---@param other TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TData:merge(other, loc)
    if other ~= nil and other.kind == "TData" and other.name == self.name and #self.args == #other.args then
        ---@type Equation[]
        local eqs = {}
        for i, a in ipairs(self.args) do
            eqs[#eqs + 1] = newEquationBestLoc(a, other.args[i], loc)
        end
        return eqs, nil
    end
    return nil, string.format("cannot match %s and %s", other:code(""), self:code(""))
end

---@param subst table<integer, TypedType>
---@return TypedType|nil t
---@return string|nil err
function TData:mapTo(subst)
    for i, a in ipairs(self.args) do
        local x, err = a:mapTo(subst)
        if err ~= nil then
            return nil, err
        end
        self.args[i] = x
    end
    return self, nil
end

---@param other TypedType
---@param req table<FullIdentifier, true>|nil
---@return boolean
function TData:equalsTo(other, req)
    if other == nil or other.kind ~= "TData" then
        return false
    end
    if other.name ~= self.name then
        return false
    end
    if req ~= nil and req[self.name] then
        return true
    end
    ---@type table<FullIdentifier, true>
    local newReq = { [self.name] = true }
    if #self.args ~= #other.args then
        return false
    end
    for i, a in ipairs(self.args) do
        if not a:equalsTo(other.args[i], newReq) then
            return false
        end
    end
    return true
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TData:code(currentModule)
    local s = tostring(self.name)
    if currentModule ~= nil and currentModule ~= "" then
        local pref = currentModule .. "."
        if s:sub(1, #pref) == pref then
            s = s:sub(#pref + 1)
        end
    end
    local parts = {}
    for _, x in ipairs(self.args) do
        parts[#parts + 1] = x:code("")
    end
    local tp = table.concat(parts, ", ")
    if tp ~= "" then
        tp = "[" .. tp .. "]"
    end
    return s .. tp
end

return {
    TData = TData,
    DataOption = DataOption,
}
