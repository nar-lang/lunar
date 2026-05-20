local TypedExpression = require("compiler.ast.typed.expression").TypedExpression
local newEquation = require("compiler.ast.typed.equation").newEquation
local TyRecordType = require("compiler.ast.typed.type_record").TyRecordType
local builtins = require("compiler.common.builtins")
local bytecode = require("compiler.bytecode.op")

---@class TyUpdate : TypedExpression
---@field kind "TyUpdate"
---@field location Location
---@field type_ TypedType
---@field recordName Identifier
---@field target TypedPattern|nil
---@field moduleName QualifiedIdentifier|""
---@field definition TypedDefinition|nil
---@field fields TyRecordField[]
local TyUpdate = setmetatable({}, { __index = TypedExpression })
TyUpdate.__index = TyUpdate

---@param ctx SolvingContext
---@param loc Location
---@param moduleName QualifiedIdentifier
---@param definitionName Identifier
---@param targetDef TypedDefinition|nil
---@param fields TyRecordField[]
---@return TyUpdate
function TyUpdate.newGlobal(ctx, loc, moduleName, definitionName, targetDef, fields)
    local e = setmetatable({
        kind = "TyUpdate",
        location = loc,
        type_ = nil,
        recordName = definitionName,
        target = nil,
        moduleName = moduleName,
        definition = targetDef,
        fields = fields or {},
    }, TyUpdate)
    ctx:annotateExpression(e)
    return e
end

---@param ctx SolvingContext
---@param loc Location
---@param recordName Identifier
---@param target TypedPattern
---@param fields TyRecordField[]
---@return TyUpdate
function TyUpdate.newLocal(ctx, loc, recordName, target, fields)
    local e = setmetatable({
        kind = "TyUpdate",
        location = loc,
        type_ = nil,
        recordName = recordName,
        target = target,
        moduleName = "",
        definition = nil,
        fields = fields or {},
    }, TyUpdate)
    ctx:annotateExpression(e)
    return e
end

---@return string|nil err
function TyUpdate:checkPatterns()
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
function TyUpdate:mapTypes(subst)
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
function TyUpdate:code(currentModule)
    local parts = {}
    for _, f in ipairs(self.fields) do
        parts[#parts + 1] = string.format("%s = %s", f.name, f.value:code(currentModule))
    end
    return string.format("{%s | %s}", self.recordName, table.concat(parts, ", "))
end

---@param eqs Equation[]
---@param loc Location|nil
---@param localDefs TypedLocalTypesMap
---@param ctx SolvingContext
---@param stack TypedDefinition[]
---@return Equation[]|nil eqs
---@return string|nil err
function TyUpdate:appendEquations(eqs, loc, localDefs, ctx, stack)
    ---@type table<Identifier, TypedType>
    local fieldTypes = {}
    for _, f in ipairs(self.fields) do
        fieldTypes[f.name] = f.type_
    end
    eqs[#eqs + 1] = newEquation(self, self.type_, TyRecordType.new(self.location, fieldTypes, true))
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
    if self.moduleName ~= nil and self.moduleName ~= "" then
        if self.definition == nil then
            return nil, string.format("definition `%s` not found",
                builtins.makeFullIdentifier(self.moduleName, self.recordName))
        end
        local defType, err = self.definition:uniqueType(ctx, stack)
        if err ~= nil then
            return nil, err
        end
        ---@cast defType -nil
        eqs[#eqs + 1] = newEquation(self, self.type_, defType)
    end
    return eqs, nil
end

---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function TyUpdate:appendBytecode(ops, locations, binary, hash)
    if self.moduleName ~= nil and self.moduleName ~= "" then
        local id = builtins.makeFullIdentifier(self.moduleName, self.recordName)
        ops, locations = bytecode.appendLoadGlobal(hash.funcsMap[id], self.location, ops, locations)
    else
        ops, locations = bytecode.appendLoadLocal(self.recordName, self.location, ops, locations, binary, hash)
    end
    for _, f in ipairs(self.fields) do
        ops, locations = f.value:appendBytecode(ops, locations, binary, hash)
        ops, locations = bytecode.appendUpdate(f.name, f.location, ops, locations, binary, hash)
    end
    return ops, locations
end

return { TyUpdate = TyUpdate }
