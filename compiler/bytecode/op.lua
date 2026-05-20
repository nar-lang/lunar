local PackedInt = require("compiler.bytecode.const_hash").PackedInt
local PackedFloat = require("compiler.bytecode.const_hash").PackedFloat
---Bytecode op encoder, mirrors nar-compiler/bytecode/op.go byte-for-byte.
---
---Layout of a single 64-bit op word (little-endian semantics, but stored as a
---Lua integer):
---   bits  0..7  : OpKind (uint8)
---   bits  8..15 : b      (uint8)
---   bits 16..23 : c      (uint8)
---   bits 32..63 : a      (uint32)
---
---Lua 5.3+ has 64-bit signed integers and bitwise operators, so we can pack
---the word directly. uint32 `a` fits into the top half without ever colliding
---with the low byte fields.

local Op                    = {}

---@alias OpKind integer
---@alias PatternKind integer
---@alias ConstKind integer
---@alias StackKind integer
---@alias SwapPopMode integer
---@alias ObjectKind integer
---@alias StringHash integer
---@alias ConstHash integer
---@alias Pointer integer

-- OpKind ---------------------------------------------------------------------
Op.OP_KIND_NONE             = 0
Op.OP_KIND_LOAD_LOCAL       = 1
Op.OP_KIND_LOAD_GLOBAL      = 2
Op.OP_KIND_LOAD_CONST       = 3
Op.OP_KIND_APPLY            = 4
Op.OP_KIND_CALL             = 5
Op.OP_KIND_JUMP             = 6
Op.OP_KIND_MAKE_OBJECT      = 7
Op.OP_KIND_MAKE_PATTERN     = 8
Op.OP_KIND_ACCESS           = 9
Op.OP_KIND_UPDATE           = 10
Op.OP_KIND_SWAP_POP         = 11

-- PatternKind ----------------------------------------------------------------
Op.PATTERN_KIND_NONE        = 0
Op.PATTERN_KIND_ALIAS       = 1
Op.PATTERN_KIND_ANY         = 2
Op.PATTERN_KIND_CONS        = 3
Op.PATTERN_KIND_CONST       = 4
Op.PATTERN_KIND_DATA_OPTION = 5
Op.PATTERN_KIND_LIST        = 6
Op.PATTERN_KIND_NAMED       = 7
Op.PATTERN_KIND_RECORD      = 8
Op.PATTERN_KIND_TUPLE       = 9

-- ConstKind ------------------------------------------------------------------
Op.CONST_KIND_NONE          = 0
Op.CONST_KIND_UNIT          = 1
Op.CONST_KIND_CHAR          = 2
Op.CONST_KIND_INT           = 3
Op.CONST_KIND_FLOAT         = 4
Op.CONST_KIND_STRING        = 5

-- StackKind ------------------------------------------------------------------
Op.STACK_KIND_NONE          = 0
Op.STACK_KIND_OBJECT        = 1
Op.STACK_KIND_PATTERN       = 2

-- ObjectKind -----------------------------------------------------------------
Op.OBJECT_KIND_NONE         = 0
Op.OBJECT_KIND_LIST         = 1
Op.OBJECT_KIND_TUPLE        = 2
Op.OBJECT_KIND_RECORD       = 3
Op.OBJECT_KIND_OPTION       = 4

-- SwapPopMode ----------------------------------------------------------------
Op.SWAP_POP_MODE_NONE       = 0
Op.SWAP_POP_MODE_BOTH       = 1
Op.SWAP_POP_MODE_POP        = 2

-- ----------------------------------------------------------------------------
-- Op packing helpers
-- ----------------------------------------------------------------------------

local U8_MASK               = 0xff
local U32_MASK              = 0xffffffff

---@param kind OpKind
---@param b integer
---@param c integer
---@param a integer
---@return integer op
local function buildOp(kind, b, c, a)
    return (kind & U8_MASK)
        | ((b & U8_MASK) << 8)
        | ((c & U8_MASK) << 16)
        | ((a & U32_MASK) << 32)
end

---@param op integer
---@return OpKind kind, integer b, integer c, integer a
local function decompose(op)
    local kind = op & U8_MASK
    local b = (op >> 8) & U8_MASK
    local c = (op >> 16) & U8_MASK
    local a = (op >> 32) & U32_MASK
    return kind, b, c, a
end

---Returns a new op with the `a` (delta) field replaced. `delta` may be a
---signed 32-bit integer; we re-encode it as uint32 to mirror Go's
---`Op.WithDelta(int32)`.
---@param op integer
---@param delta integer
---@return integer
local function withDelta(op, delta)
    local kind, b, c, _ = decompose(op)
    return buildOp(kind, b, c, delta & U32_MASK)
end

Op.buildOp = buildOp
Op.decompose = decompose
Op.withDelta = withDelta

-- ----------------------------------------------------------------------------
-- Append helpers
-- ----------------------------------------------------------------------------

---@param locations integer[][] each entry is { line, column }
---@param loc Location
local function appendLoc(locations, loc)
    -- Mirrors Go's Location.Bytecode(): returns 1-based start line/column.
    local line, column = loc:getLineAndColumn()
    locations[#locations + 1] = { line, column }
end

---@param name string
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function Op.appendLoadLocal(name, loc, ops, locations, binary, hash)
    local h = hash:hashString(name, binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_LOAD_LOCAL, 0, 0, h)
    appendLoc(locations, loc)
    return ops, locations
end

---@param ptr Pointer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@return integer[], integer[][]
function Op.appendLoadGlobal(ptr, loc, ops, locations)
    ops[#ops + 1] = buildOp(Op.OP_KIND_LOAD_GLOBAL, 0, 0, ptr)
    appendLoc(locations, loc)
    return ops, locations
end

---@param stack integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@return integer[], integer[][]
function Op.appendLoadConstUnitValue(stack, loc, ops, locations, binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_LOAD_CONST, stack, Op.CONST_KIND_UNIT, 0)
    appendLoc(locations, loc)
    return ops, locations
end

---@param v integer rune (unicode codepoint)
---@param stack integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@return integer[], integer[][]
function Op.appendLoadConstCharValue(v, stack, loc, ops, locations, binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_LOAD_CONST, stack, Op.CONST_KIND_CHAR, v)
    appendLoc(locations, loc)
    return ops, locations
end

---@param v integer
---@param stack integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function Op.appendLoadConstIntValue(v, stack, loc, ops, locations, binary, hash)
    local idx = hash:hashConst(PackedInt.new(v), binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_LOAD_CONST, stack, Op.CONST_KIND_INT, idx)
    appendLoc(locations, loc)
    return ops, locations
end

---@param v number
---@param stack integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function Op.appendLoadConstFloatValue(v, stack, loc, ops, locations, binary, hash)
    local idx = hash:hashConst(PackedFloat.new(v), binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_LOAD_CONST, stack, Op.CONST_KIND_FLOAT, idx)
    appendLoc(locations, loc)
    return ops, locations
end

---@param v string
---@param stack integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function Op.appendLoadConstStringValue(v, stack, loc, ops, locations, binary, hash)
    local idx = hash:hashString(v, binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_LOAD_CONST, stack, Op.CONST_KIND_STRING, idx)
    appendLoc(locations, loc)
    return ops, locations
end

---@param numArgs integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@return integer[], integer[][]
function Op.appendApply(numArgs, loc, ops, locations)
    ops[#ops + 1] = buildOp(Op.OP_KIND_APPLY, numArgs, 0, 0)
    appendLoc(locations, loc)
    return ops, locations
end

---@param name string
---@param numArgs integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function Op.appendCall(name, numArgs, loc, ops, locations, binary, hash)
    local h = hash:hashString(name, binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_CALL, numArgs, 0, h)
    appendLoc(locations, loc)
    return ops, locations
end

---@param jumpDelta integer
---@param conditional boolean
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@return integer[], integer[][]
function Op.appendJump(jumpDelta, conditional, loc, ops, locations)
    local v = 0
    if conditional then
        v = 1
    end
    ops[#ops + 1] = buildOp(Op.OP_KIND_JUMP, v, 0, jumpDelta & U32_MASK)
    appendLoc(locations, loc)
    return ops, locations
end

---@param kind ObjectKind
---@param numArgs integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@return integer[], integer[][]
function Op.appendMakeObject(kind, numArgs, loc, ops, locations)
    ops[#ops + 1] = buildOp(Op.OP_KIND_MAKE_OBJECT, kind, 0, numArgs)
    appendLoc(locations, loc)
    return ops, locations
end

---@param kind PatternKind
---@param name string
---@param numNested integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function Op.appendMakePattern(kind, name, numNested, loc, ops, locations, binary, hash)
    local h = hash:hashString(name, binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_MAKE_PATTERN, kind, numNested, h)
    appendLoc(locations, loc)
    return ops, locations
end

---@param kind PatternKind
---@param numNested integer
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@return integer[], integer[][]
function Op.appendMakePatternLong(kind, numNested, loc, ops, locations, binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_MAKE_PATTERN, kind, 0, numNested)
    appendLoc(locations, loc)
    return ops, locations
end

---@param field string
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function Op.appendAccess(field, loc, ops, locations, binary, hash)
    local h = hash:hashString(field, binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_ACCESS, 0, 0, h)
    appendLoc(locations, loc)
    return ops, locations
end

---@param field string
---@param loc Location
---@param ops integer[]
---@param locations integer[][]
---@param binary Binary
---@param hash BinaryHash
---@return integer[], integer[][]
function Op.appendUpdate(field, loc, ops, locations, binary, hash)
    local h = hash:hashString(field, binary)
    ops[#ops + 1] = buildOp(Op.OP_KIND_UPDATE, 0, 0, h)
    appendLoc(locations, loc)
    return ops, locations
end

---@param loc Location
---@param mode SwapPopMode
---@param ops integer[]
---@param locations integer[][]
---@return integer[], integer[][]
function Op.appendSwapPop(loc, mode, ops, locations)
    ops[#ops + 1] = buildOp(Op.OP_KIND_SWAP_POP, mode, 0, 0)
    appendLoc(locations, loc)
    return ops, locations
end

return Op
