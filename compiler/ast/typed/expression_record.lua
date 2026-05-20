local TypedExpression = require("lunar.compiler.ast.typed.expression").TypedExpression
local newEquation = require("lunar.compiler.ast.typed.equation").newEquation
local TyRecordType = require("lunar.compiler.ast.typed.type_record").TyRecordType
local CString = require("lunar.compiler.ast.const").CString
local bytecode = require("lunar.compiler.bytecode.op")

---@class TyRecordField
---@field location Location
---@field type_ TypedType
---@field name Identifier
---@field value TypedExpression
local TyRecordField = {}
TyRecordField.__index = TyRecordField

---@param ctx SolvingContext
---@param loc Location
---@param name Identifier
---@param value TypedExpression
---@return TyRecordField
function TyRecordField.new(ctx, loc, name, value)
    local f = setmetatable({
        location = loc,
        type_ = nil,
        name = name,
        value = value,
    }, TyRecordField)
    f.type_ = ctx:newTypeAnnotation(f)
    return f
end

---@class TyRecord : TypedExpression
---@field kind "TyRecord"
---@field location Location
---@field type_ TypedType
---@field fields TyRecordField[]
local TyRecord = setmetatable({}, { __index = TypedExpression })
TyRecord.__index = TyRecord

---@param ctx SolvingContext
---@param loc Location
---@param fields TyRecordField[]
---@return TyRecord
function TyRecord.new(ctx, loc, fields)
    local e = setmetatable({
        kind = "TyRecord",
        location = loc,
        type_ = nil,
        fields = fields or {},
    }, TyRecord)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyRecord:checkPatterns()
    for _, f in ipairs(self.fields) do
        local err = f.value:checkPatterns()
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyRecord:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    ---@cast t -nil
    self.type_ = t
    for _, f in ipairs(self.fields) do
        local ft, ferr = f.type_:mapTo(subst)
        if ferr ~= nil then
            return ferr
        end
        ---@cast ft -nil
        f.type_ = ft
        err = f.value:mapTypes(subst)
        if err ~= nil then
            return err
        end
    end
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyRecord:code(currentModule)
    local parts = {}
    for _, f in ipairs(self.fields) do
        parts[#parts + 1] = string.format("%s = %s", f.name, f.value:code(currentModule))
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyRecord:appendEquations(eqs, loc, localDefs, ctx, stack)
    ---@type table<Identifier, TypedType>
    local fieldTypes = {}
    for _, f in ipairs(self.fields) do
        fieldTypes[f.name] = f.type_
    end
    local typeRecord = TyRecordType.new(self.location, fieldTypes, false)
    eqs[#eqs + 1] = newEquation(self, self.type_, typeRecord)
    for _, f in ipairs(self.fields) do
        eqs[#eqs + 1] = newEquation(self, f.type_, f.value:getType())
    end
    for _, f in ipairs(self.fields) do
        local newEqs, err = f.value:appendEquations(eqs, loc, localDefs, ctx, stack)
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
function TyRecord:appendBytecode(ops, locations, binary, hash)
    for _, f in ipairs(self.fields) do
        ops, locations = f.value:appendBytecode(ops, locations, binary, hash)
        ops, locations = CString.new(f.name):appendBytecode(
            bytecode.STACK_KIND_OBJECT, f.location, ops, locations, binary, hash)
    end
    return bytecode.appendMakeObject(bytecode.OBJECT_KIND_RECORD, #self.fields, self.location, ops, locations)
end

return {
    TyRecord = TyRecord,
    TyRecordField = TyRecordField,
}
