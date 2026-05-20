local TypedType = require("lunar.compiler.ast.typed.type").TypedType
local newEquationBestLoc = require("lunar.compiler.ast.typed.equation").newEquationBestLoc

---@class TyDataOption
---@field name DataOptionIdentifier
---@field values TypedType[]
local TyDataOption = {}
TyDataOption.__index = TyDataOption

---@param name DataOptionIdentifier
---@param values TypedType[]|nil
---@return TyDataOption
function TyDataOption.new(name, values)
    return setmetatable({
        name = name,
        values = values or {},
    }, TyDataOption)
end

---@class TyData : TypedType
---@field kind "TData"
---@field location Location
---@field name FullIdentifier
---@field args TypedType[]
---@field options TyDataOption[]
local TyData = setmetatable({}, { __index = TypedType })
TyData.__index = TyData

---@param loc Location
---@param name FullIdentifier
---@param args TypedType[]|nil
---@param options TyDataOption[]|nil
---@return TyData
function TyData.new(loc, name, args, options)
    return setmetatable({
        kind = "TData",
        location = loc,
        name = name,
        args = args or {},
        options = options or {},
    }, TyData)
end

---@param options TyDataOption[]
function TyData:setOptions(options)
    self.options = options or {}
end

---@param ctx SolvingContext
---@param ubMap table<integer, integer>
---@return TyData
function TyData:makeUnique(ctx, ubMap)
    ---@type TypedType[]
    local args = {}
    for i, a in ipairs(self.args) do
        args[i] = a:makeUnique(ctx, ubMap)
    end
    return TyData.new(self.location, self.name, args, self.options)
end

---@param other TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TyData:merge(other, loc)
    if other ~= nil and other.kind == "TData" then
        ---@cast other TyData
        if other.name == self.name and #self.args == #other.args then
            ---@type Equation[]
            local eqs = {}
            for i, a in ipairs(self.args) do
                eqs[#eqs + 1] = newEquationBestLoc(a, other.args[i], loc)
            end
            return eqs, nil
        end
    end
    return nil, string.format("cannot match %s and %s", other:code(""), self:code(""))
end

---@param subst table<integer, TypedType>
---@return TypedType|nil t
---@return string|nil err
function TyData:mapTo(subst)
    for i, a in ipairs(self.args) do
        local x, err = a:mapTo(subst)
        if err ~= nil then
            return nil, err
        end
        ---@cast x -nil
        self.args[i] = x
    end
    return self, nil
end

---@param other TypedType
---@param req table<FullIdentifier, true>|nil
---@return boolean
function TyData:equalsTo(other, req)
    if other == nil or other.kind ~= "TData" then
        return false
    end
    ---@cast other TyData
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
function TyData:code(currentModule)
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
    TyData = TyData,
    TyDataOption = TyDataOption,
}
