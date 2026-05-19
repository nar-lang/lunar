---@class ConstValue
---@field kind "CChar"|"CInt"|"CFloat"|"CString"|"CUnit"

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

return {
    CChar = CChar,
    CInt = CInt,
    CFloat = CFloat,
    CString = CString,
    CUnit = CUnit,
}
