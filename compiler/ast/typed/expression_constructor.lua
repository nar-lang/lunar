local TypedExpression = require("compiler.ast.typed.expression").TypedExpression
local newEquation = require("compiler.ast.typed.equation").newEquation
local TData = require("compiler.ast.typed.type_data").TData
local CString = require("compiler.ast.const").CString
local builtins = require("compiler.common.builtins")
local bytecode = require("compiler.bytecode.op")

---@class TyConstructor : TypedExpression
---@field kind "TyConstructor"
---@field location Location
---@field type_ TypedType
---@field dataName FullIdentifier
---@field optionName Identifier
---@field dataType TData|nil
---@field args TypedExpression[]
local TyConstructor = setmetatable({}, { __index = TypedExpression })
TyConstructor.__index = TyConstructor

---@param ctx SolvingContext
---@param loc Location
---@param dataName FullIdentifier
---@param optionName Identifier
---@param dataType TData|nil
---@param args TypedExpression[]
---@return TyConstructor
function TyConstructor.new(ctx, loc, dataName, optionName, dataType, args)
    local e = setmetatable({
        kind = "TyConstructor",
        location = loc,
        type_ = nil,
        dataName = dataName,
        optionName = optionName,
        dataType = dataType,
        args = args or {},
    }, TyConstructor)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyConstructor:checkPatterns()
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
function TyConstructor:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    for _, arg in ipairs(self.args) do
        err = arg:mapTypes(subst)
        if err ~= nil then
            return err
        end
    end
    if self.dataType ~= nil then
        local xdt, derr = self.dataType:mapTo(subst)
        if derr ~= nil then
            return derr
        end
        if xdt == nil or xdt.kind ~= "TData" then
            return "failed to map data type"
        end
        self.dataType = xdt
    end
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyConstructor:code(currentModule)
    local parts = {}
    for _, a in ipairs(self.args) do
        parts[#parts + 1] = a:code(currentModule)
    end
    local args = table.concat(parts, ", ")
    if args ~= "" then
        args = "(" .. args .. ")"
    end
    return string.format("%s%s", self.dataName, args)
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyConstructor:appendEquations(eqs, loc, localDefs, ctx, stack)
    local r
    if self.dataType == nil then
        r = TData.new(self.location, self.dataName, nil, nil)
    else
        r = TData.new(self.location, self.dataName, self.dataType.args, self.dataType.options)
    end
    eqs[#eqs + 1] = newEquation(self, self.type_, r)
    for _, a in ipairs(self.args) do
        local newEqs, err = a:appendEquations(eqs, loc, localDefs, ctx, stack)
        if err ~= nil then
            return nil, err
        end
        eqs = newEqs
    end
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyConstructor:appendBytecode(ops, locations, binary, hash)
    for _, arg in ipairs(self.args) do
        ops, locations = arg:appendBytecode(ops, locations, binary, hash)
    end
    local tag = CString.new(builtins.makeDataOptionIdentifier(self.dataName, self.optionName))
    ops, locations = tag:appendBytecode(bytecode.STACK_KIND_OBJECT, self.location, ops, locations, binary, hash)
    return bytecode.appendMakeObject(bytecode.OBJECT_KIND_OPTION, #self.args, self.location, ops, locations)
end

return { TyConstructor = TyConstructor }
