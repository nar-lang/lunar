---PackedConst values (int / float) used by ConstHashMap dedup.
---Mirrors nar-compiler/bytecode/const_hash.go.

local ConstHash = {}

ConstHash.KIND_NONE  = 0
ConstHash.KIND_INT   = 1
ConstHash.KIND_FLOAT = 2

---@class PackedInt
---@field value integer
local PackedInt = {}
PackedInt.__index = PackedInt

---@param value integer
---@return PackedInt
function PackedInt.new(value)
    return setmetatable({ value = value }, PackedInt)
end

---@return integer
function PackedInt:pack()
    -- Go stores Pack() as uint64(value) — Lua's integer is signed 64-bit,
    -- but bit-identical representation. Callers must serialize the raw
    -- 8 bytes (we always use `<i8`).
    return self.value
end

---@return integer kind ConstHash.KIND_INT
function PackedInt:kind()
    return ConstHash.KIND_INT
end

---@return string
function PackedInt:hashKey()
    return "i" .. tostring(self.value)
end

---@class PackedFloat
---@field value number
local PackedFloat = {}
PackedFloat.__index = PackedFloat

---@param value number
---@return PackedFloat
function PackedFloat.new(value)
    return setmetatable({ value = value }, PackedFloat)
end

---@return integer raw uint64 bits of the float64 value
function PackedFloat:pack()
    -- math.Float64bits equivalent. Lua 5.3+ guarantees `<d`/`<I8` are exact
    -- little-endian IEEE-754 forms.
    local bytes = string.pack("<d", self.value)
    local bits = string.unpack("<I8", bytes)
    return bits
end

---@return integer kind ConstHash.KIND_FLOAT
function PackedFloat:kind()
    return ConstHash.KIND_FLOAT
end

---@return string
function PackedFloat:hashKey()
    -- Use the raw 8-byte representation as the key so 0.0 and -0.0 hash
    -- separately just like Go's map keyed on PackedFloat struct.
    return "f" .. string.pack("<d", self.value)
end

ConstHash.PackedInt = PackedInt
ConstHash.PackedFloat = PackedFloat

return ConstHash
