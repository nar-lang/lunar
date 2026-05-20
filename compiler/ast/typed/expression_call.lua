local TypedExpression = require("lunar.compiler.ast.typed.expression").TypedExpression
local bytecode = require("lunar.compiler.bytecode.op")

---@class TyCall : TypedExpression
---@field kind "TyCall"
---@field location Location
---@field type_ TypedType
---@field name FullIdentifier
---@field args TypedExpression[]
local TyCall = setmetatable({}, { __index = TypedExpression })
TyCall.__index = TyCall

---@param ctx SolvingContext
---@param loc Location
---@param name FullIdentifier
---@param args TypedExpression[]
---@return TyCall|nil
---@return string|nil err
function TyCall.new(ctx, loc, name, args)
    if #args > 255 then
        return nil, "too many arguments (max 255)"
    end
    local e = setmetatable({
        kind = "TyCall",
        location = loc,
        type_ = nil,
        name = name,
        args = args or {},
    }, TyCall)
    ctx:annotateExpression(e)
    return e, nil
end

---@return string|nil err
function TyCall:checkPatterns()
    for _, arg in ipairs(self.args) do
        local err = arg:checkPatterns()
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyCall:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    ---@cast t -nil
    self.type_ = t
    for _, arg in ipairs(self.args) do
        err = arg:mapTypes(subst)
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyCall:code(currentModule)
    local parts = {}
    for _, a in ipairs(self.args) do
        parts[#parts + 1] = a:code(currentModule)
    end
    return string.format("%s(%s)", self.name, table.concat(parts, ", "))
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyCall:appendEquations(eqs, loc, localDefs, ctx, stack)
    for _, a in ipairs(self.args) do
        local newEqs, err = a:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast newEqs -nil
        eqs = newEqs
    end
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyCall:appendBytecode(ops, locations, binary, hash)
    for _, arg in ipairs(self.args) do
        ops, locations = arg:appendBytecode(ops, locations, binary, hash)
    end
    return bytecode.appendCall(self.name, #self.args, self.location, ops, locations, binary, hash)
end

return { TyCall = TyCall }
