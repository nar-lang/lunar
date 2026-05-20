---@class ConstValue
---@field kind "CChar"|"CInt"|"CFloat"|"CString"|"CUnit"
---@field equals fun(self: ConstValue, other: ConstValue): boolean
---@field appendBytecode fun(self: ConstValue, stackKind: StackKind, loc: Location, ops: integer[], locations: integer[][], binary: Binary, hash: BinaryHash): integer[], integer[][]

local bytecode = require("lunar.compiler.bytecode.op")

---@class CChar : ConstValue
---@field kind "CChar"
---@field value string utf-8 character
local CChar = {}
CChar.__index = CChar

---@param value string
---@return CChar
function CChar.new(value)
    return setmetatable({ kind = "CChar", value = value }, CChar)
end

---@param other ConstValue
---@return boolean
function CChar:equals(other)
    if other.kind ~= "CChar" then
        return false
    end
    ---@cast other CChar
    return other.value == self.value
end

---@param stackKind StackKind
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[] ops, integer[][] locations
function CChar:appendBytecode(stackKind, loc, ops, locations, binary, hash)
    -- Go stores the value as a single rune (codepoint). Lua keeps it as a
    -- UTF-8 string; decode to codepoint for byte-identical output.
    local codepoint = utf8.codepoint(self.value, 1)
    return bytecode.appendLoadConstCharValue(codepoint, stackKind, loc, ops, locations, binary)
end

---@class CInt : ConstValue
---@field kind "CInt"
---@field value integer
local CInt = {}
CInt.__index = CInt

---@param value integer
---@return CInt
function CInt.new(value)
    return setmetatable({ kind = "CInt", value = value }, CInt)
end

---@param other ConstValue
---@return boolean
function CInt:equals(other)
    if other.kind ~= "CInt" then
        return false
    end
    ---@cast other CInt
    return other.value == self.value
end

---@param stackKind StackKind
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[] ops, integer[][] locations
function CInt:appendBytecode(stackKind, loc, ops, locations, binary, hash)
    return bytecode.appendLoadConstIntValue(self.value, stackKind, loc, ops, locations, binary, hash)
end

---@class CFloat : ConstValue
---@field kind "CFloat"
---@field value number
local CFloat = {}
CFloat.__index = CFloat

---@param value number
---@return CFloat
function CFloat.new(value)
    return setmetatable({ kind = "CFloat", value = value }, CFloat)
end

---@param other ConstValue
---@return boolean
function CFloat:equals(other)
    if other.kind ~= "CFloat" then
        return false
    end
    ---@cast other CFloat
    return other.value == self.value
end

---@param stackKind StackKind
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[] ops, integer[][] locations
function CFloat:appendBytecode(stackKind, loc, ops, locations, binary, hash)
    return bytecode.appendLoadConstFloatValue(self.value, stackKind, loc, ops, locations, binary, hash)
end

---@class CString : ConstValue
---@field kind "CString"
---@field value string
local CString = {}
CString.__index = CString

---@param value string
---@return CString
function CString.new(value)
    return setmetatable({ kind = "CString", value = value }, CString)
end

---@param other ConstValue
---@return boolean
function CString:equals(other)
    if other.kind ~= "CString" then
        return false
    end
    ---@cast other CString
    return other.value == self.value
end

---@param stackKind StackKind
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[] ops, integer[][] locations
function CString:appendBytecode(stackKind, loc, ops, locations, binary, hash)
    return bytecode.appendLoadConstStringValue(self.value, stackKind, loc, ops, locations, binary, hash)
end

---@class CUnit : ConstValue
---@field kind "CUnit"
local CUnit = {}
CUnit.__index = CUnit

---@return CUnit
function CUnit.new()
    return setmetatable({ kind = "CUnit" }, CUnit)
end

---@param other ConstValue
---@return boolean
function CUnit:equals(other)
    return other.kind == "CUnit"
end

---@param stackKind StackKind
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[] ops, integer[][] locations
function CUnit:appendBytecode(stackKind, loc, ops, locations, binary, hash)
    return bytecode.appendLoadConstUnitValue(stackKind, loc, ops, locations, binary)
end

return {
    CChar = CChar,
    CInt = CInt,
    CFloat = CFloat,
    CString = CString,
    CUnit = CUnit,
}
