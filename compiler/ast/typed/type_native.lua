local TypedType = require("compiler.ast.typed.type").TypedType
local newEquationBestLoc = require("compiler.ast.typed.equation").newEquationBestLoc

---@class TNative : TypedType
---@field kind "TNative"
---@field location Location
---@field name FullIdentifier
---@field args TypedType[]
local TNative = setmetatable({}, { __index = TypedType })
TNative.__index = TNative

---@param loc Location
---@param name FullIdentifier
---@param args TypedType[]|nil
---@return TNative
function TNative.new(loc, name, args)
    return setmetatable({
        kind = "TNative",
        location = loc,
        name = name,
        args = args or {},
    }, TNative)
end

---@param ctx SolvingContext
---@param ubMap table<integer, integer>
---@return TNative
function TNative:makeUnique(ctx, ubMap)
    ---@type TypedType[]
    local args = {}
    for i, a in ipairs(self.args) do
        args[i] = a:makeUnique(ctx, ubMap)
    end
    return TNative.new(self.location, self.name, args)
end

---@param other TypedType
---@param loc Location
---@return Equation[]|nil eqs
---@return string|nil err
function TNative:merge(other, loc)
    if other ~= nil and other.kind == "TNative" then
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
function TNative:mapTo(subst)
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
function TNative:equalsTo(other, req)
    if other == nil or other.kind ~= "TNative" then
        return false
    end
    if other.name ~= self.name then
        return false
    end
    if #self.args ~= #other.args then
        return false
    end
    for i, a in ipairs(self.args) do
        if not a:equalsTo(other.args[i], req) then
            return false
        end
    end
    return true
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TNative:code(currentModule)
    local parts = {}
    for _, x in ipairs(self.args) do
        parts[#parts + 1] = x:code("")
    end
    local tp = table.concat(parts, ", ")
    if tp ~= "" then
        tp = "[" .. tp .. "]"
    end
    local s = tostring(self.name)
    if currentModule ~= nil and currentModule ~= "" then
        local pref = currentModule .. "."
        if s:sub(1, #pref) == pref then
            s = s:sub(#pref + 1)
        end
    end
    return s .. tp
end

return { TNative = TNative }
