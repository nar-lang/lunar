local TypedPattern = require("compiler.ast.typed.pattern").TypedPattern
local newEquation = require("compiler.ast.typed.equation").newEquation
local TRecord = require("compiler.ast.typed.type_record").TRecord
local SimpleAnything = require("compiler.ast.typed.simple_pattern").SimpleAnything
local CString = require("compiler.ast.const").CString
local bytecode = require("compiler.bytecode.op")

---@class TyPRecordField
---@field location Location
---@field name Identifier
---@field type_ TypedType
---@field declaredType TypedType|nil
local TyPRecordField = {}
TyPRecordField.__index = TyPRecordField

---@param ctx SolvingContext
---@param loc Location
---@param name Identifier
---@param declaredType TypedType|nil
---@return TyPRecordField
function TyPRecordField.new(ctx, loc, name, declaredType)
    local f = setmetatable({
        location = loc,
        name = name,
        type_ = nil,
        declaredType = declaredType,
    }, TyPRecordField)
    f.type_ = ctx:newTypeAnnotation(f)
    return f
end

---@class TyPRecord : TypedPattern
---@field kind "TyPRecord"
---@field location Location
---@field type_ TypedType
---@field declaredType TypedType|nil
---@field fields TyPRecordField[]
local TyPRecord = setmetatable({}, { __index = TypedPattern })
TyPRecord.__index = TyPRecord

---@param ctx SolvingContext
---@param loc Location
---@param declaredType TypedType|nil
---@param fields TyPRecordField[]
---@return TyPRecord
function TyPRecord.new(ctx, loc, declaredType, fields)
    local p = setmetatable({
        kind = "TyPRecord",
        location = loc,
        type_ = nil,
        declaredType = declaredType,
        fields = fields or {},
    }, TyPRecord)
    ctx:annotatePattern(p)
    return p
end

---@return SimpleAnything
function TyPRecord:simplify()
    return SimpleAnything.new()
end

---@param subst table<integer, TypedType>
---@return string|nil err
function TyPRecord:mapTypes(subst)
    local t, err = self.type_:mapTo(subst)
    if err ~= nil then
        return err
    end
    self.type_ = t
    for _, f in ipairs(self.fields) do
        local ft, ferr = f.type_:mapTo(subst)
        if ferr ~= nil then
            return ferr
        end
        f.type_ = ft
    end
    return nil
end

---@param currentModule QualifiedIdentifier|""
---@return string
function TyPRecord:code(currentModule)
    local parts = {}
    for _, f in ipairs(self.fields) do
        local part = tostring(f.name)
        if f.type_ ~= nil then
            part = part .. ": " .. f.type_:code(currentModule)
        end
        parts[#parts + 1] = part
    end
    local s = string.format("{%s}", table.concat(parts, ", "))
    if self.declaredType ~= nil then
        s = s .. ": " .. self.declaredType:code(currentModule)
    end
    return s
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyPRecord:appendEquations(eqs, loc, localDefs, ctx, stack)
    ---@type table<Identifier, TypedType>
    local fields = {}
    for _, f in ipairs(self.fields) do
        fields[f.name] = f.type_
    end
    local typeRecord = TRecord.new(self.location, fields, true)
    eqs[#eqs + 1] = newEquation(self, self.type_, typeRecord)
    if self.declaredType ~= nil then
        eqs[#eqs + 1] = newEquation(self, self.type_, self.declaredType)
    end
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyPRecord:appendBytecode(ops, locations, binary, hash)
    for _, f in ipairs(self.fields) do
        ops, locations = CString.new(f.name):appendBytecode(
            bytecode.STACK_KIND_PATTERN, f.location, ops, locations, binary, hash)
    end
    return bytecode.appendMakePatternLong(bytecode.PATTERN_KIND_RECORD, #self.fields, self.location, ops, locations, binary)
end

return {
    TyPRecord = TyPRecord,
    TyPRecordField = TyPRecordField,
}
