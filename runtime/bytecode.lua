---Bytecode reader + op pre-decoder (runtime-2, optimized).
---
---Reads the same byte format as runtime/bytecode.lua (compiler.bytecode.binary
---output, format version 100) but additionally pre-decomposes every uint64
---op into a small record with pre-resolved fields, so the interpreter's hot
---loop never needs to bit-shift or do string-table / const-table lookups.
---
---Per-op record:
---   { k = opKind,
---     b = secondaryKind, c = ternaryKind, a = aField,
---     s = preResolvedString,          -- for ops that read a string by hash
---     v = preBuiltConstValue,         -- for LOAD_CONST (boxed object)
---     d = signedJumpDelta,            -- for JUMP / conditional JUMP
---     fi = preResolvedFunctionIndex,  -- for LOAD_GLOBAL (== a, kept for clarity)
---     cachedPattern = nil,            -- populated lazily on first MAKE_PATTERN
---   }
---
---Naming: ops are array-style tables, indexed only as `op.k`, `op.s`, etc.
---No hidden behavior; direct field reads only.

local Op           = require("compiler.bytecode.op")
local constHashMod = require("compiler.bytecode.const_hash")
local Object       = require("runtime.object")
local PackedInt    = constHashMod.PackedInt
local PackedFloat  = constHashMod.PackedFloat
local KIND_FLOAT   = constHashMod.KIND_FLOAT
local KIND_INT     = constHashMod.KIND_INT

local Bytecode     = {}

---@class RtFunc
---@field name      string
---@field nameIndex integer
---@field numArgs   integer
---@field ops       table[]    pre-decoded op records (see header doc)
---@field filePath  string     "" unless bytecode was compiled with debug=true
---@field locations table[]    one `{line, column}` per op when debug=true

---@class RtBytecode
---@field compilerVersion integer
---@field debug           boolean
---@field entry           string
---@field strings         string[]
---@field consts          table[]                 pre-decoded constants (`{kind, intValue|floatValue}`)
---@field functions       RtFunc[]
---@field exports         table<string, integer>  fully-qualified name -> function index
---@field packages        table<string, integer>

local SIGNATURE    = (string.byte("N") << 8)
    | (string.byte("A") << 16)
    | (string.byte("R") << 24)
local VERSION      = 100

-- ----------------------------------------------------------------------------
-- Byte reader
-- ----------------------------------------------------------------------------

local function newReader(data)
    return { data = data, pos = 1, len = #data }
end

local function fail(r, msg)
    error(string.format("bytecode: %s (at offset %d/%d)", msg, r.pos - 1, r.len))
end

local function ensure(r, need)
    if r.pos + need - 1 > r.len then
        fail(r, "unexpected end of bytecode")
    end
end

local function readU8(r)
    ensure(r, 1); local v = string.unpack("<B", r.data, r.pos); r.pos = r.pos + 1; return v
end
local function readBool(r) return readU8(r) ~= 0 end
local function readU32(r)
    ensure(r, 4); local v = string.unpack("<I4", r.data, r.pos); r.pos = r.pos + 4; return v
end
local function readI32(r)
    ensure(r, 4); local v = string.unpack("<i4", r.data, r.pos); r.pos = r.pos + 4; return v
end
local function readU64(r)
    ensure(r, 8); local v = string.unpack("<i8", r.data, r.pos); r.pos = r.pos + 8; return v
end
local function readU64Bits(r)
    ensure(r, 8); local v = string.unpack("<I8", r.data, r.pos); r.pos = r.pos + 8; return v
end
local function readString(r)
    local size = readU32(r); ensure(r, size)
    local s = string.sub(r.data, r.pos, r.pos + size - 1); r.pos = r.pos + size; return s
end

-- ----------------------------------------------------------------------------
-- Op decomposition (local copies of constants for speed)
-- ----------------------------------------------------------------------------

local OP_LOAD_LOCAL   = Op.OP_KIND_LOAD_LOCAL
local OP_LOAD_GLOBAL  = Op.OP_KIND_LOAD_GLOBAL
local OP_LOAD_CONST   = Op.OP_KIND_LOAD_CONST
local OP_APPLY        = Op.OP_KIND_APPLY
local OP_CALL         = Op.OP_KIND_CALL
local OP_JUMP         = Op.OP_KIND_JUMP
local OP_MAKE_OBJECT  = Op.OP_KIND_MAKE_OBJECT
local OP_MAKE_PATTERN = Op.OP_KIND_MAKE_PATTERN
local OP_ACCESS       = Op.OP_KIND_ACCESS
local OP_UPDATE       = Op.OP_KIND_UPDATE
local OP_SWAP_POP     = Op.OP_KIND_SWAP_POP

local CK_UNIT         = Op.CONST_KIND_UNIT
local CK_CHAR         = Op.CONST_KIND_CHAR
local CK_INT          = Op.CONST_KIND_INT
local CK_FLOAT        = Op.CONST_KIND_FLOAT
local CK_STRING       = Op.CONST_KIND_STRING

local PK_ALIAS        = Op.PATTERN_KIND_ALIAS
local PK_DATA_OPTION  = Op.PATTERN_KIND_DATA_OPTION
local PK_NAMED        = Op.PATTERN_KIND_NAMED

local U8_MASK         = 0xff
local U32_MASK        = 0xffffffff

local function decompose(op)
    return op & U8_MASK,
        (op >> 8) & U8_MASK,
        (op >> 16) & U8_MASK,
        (op >> 32) & U32_MASK
end

local function signedDelta(a)
    if a >= 0x80000000 then return a - 0x100000000 end
    return a
end

---Convert one raw uint64 op into a runtime record with pre-resolved fields.
---@param raw integer
---@param strings string[]
---@param consts table[]
---@return table
local function preDecode(raw, strings, consts)
    local k, b, c, a = decompose(raw)
    local rec = { k = k, b = b, c = c, a = a }

    if k == OP_LOAD_LOCAL then
        rec.s = strings[a + 1]
    elseif k == OP_LOAD_GLOBAL then
        rec.fi = a
    elseif k == OP_LOAD_CONST then
        if c == CK_UNIT then
            rec.v = Object.makeUnit()
        elseif c == CK_CHAR then
            rec.v = Object.makeChar(a)
        elseif c == CK_INT then
            rec.v = Object.makeInt(consts[a + 1].intValue)
        elseif c == CK_FLOAT then
            rec.v = Object.makeFloat(consts[a + 1].floatValue)
        elseif c == CK_STRING then
            rec.v = Object.makeString(strings[a + 1])
        end
    elseif k == OP_CALL then
        rec.s = strings[a + 1]
    elseif k == OP_JUMP then
        rec.d = signedDelta(a)
    elseif k == OP_MAKE_PATTERN then
        if b == PK_ALIAS or b == PK_DATA_OPTION or b == PK_NAMED then
            rec.s = strings[a + 1]
        end
    elseif k == OP_ACCESS then
        rec.s = strings[a + 1]
    elseif k == OP_UPDATE then
        rec.s = strings[a + 1]
    end

    return rec
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

---@param data string
---@return RtBytecode
function Bytecode.load(data)
    local r = newReader(data)

    if readU32(r) ~= SIGNATURE then
        fail(r, "invalid bytecode signature")
    end
    local formatVersion = readU32(r)
    if formatVersion ~= VERSION then
        fail(r, "unsupported bytecode format version " .. tostring(formatVersion))
    end

    local btc = {
        compilerVersion = readU32(r),
        debug = readBool(r),
        entry = "",
        strings = {},
        consts = {},
        functions = {},
        exports = {},
        packages = {},
    }

    btc.entry = readString(r)

    local numStrings = readU32(r)
    for i = 1, numStrings do btc.strings[i] = readString(r) end

    local numConsts = readU32(r)
    for i = 1, numConsts do
        local kind = readU8(r)
        if kind == KIND_FLOAT then
            local bits = readU64Bits(r)
            local value = string.unpack("<d", string.pack("<I8", bits))
            btc.consts[i] = { kind = kind, floatValue = value }
        elseif kind == KIND_INT then
            btc.consts[i] = { kind = kind, intValue = readU64(r) }
        else
            btc.consts[i] = { kind = kind, intValue = readU64Bits(r) }
        end
    end

    local numFunctions = readU32(r)
    -- First pass: read raw ops + headers; we need all functions parsed
    -- before LOAD_GLOBAL can be linked.
    local raw = {}
    for i = 1, numFunctions do
        local nameIndex = readU32(r)
        local numArgs = readU32(r)
        local numOps = readU32(r)
        local ops = {}
        for j = 1, numOps do ops[j] = readU64(r) end

        local filePath, locations = "", {}
        if btc.debug then
            filePath = readString(r)
            for j = 1, numOps do
                local line, column = readU32(r), readU32(r)
                locations[j] = { line, column }
            end
        end

        raw[i] = {
            name = btc.strings[nameIndex + 1] or "",
            nameIndex = nameIndex,
            numArgs = numArgs,
            rawOps = ops,
            filePath = filePath,
            locations = locations,
        }
    end

    -- Pre-decode ops for each function (uses btc.strings + btc.consts).
    for i = 1, numFunctions do
        local f = raw[i]
        local decoded = {}
        local rawOps = f.rawOps
        for j = 1, #rawOps do
            decoded[j] = preDecode(rawOps[j], btc.strings, btc.consts)
        end
        btc.functions[i] = {
            name = f.name,
            nameIndex = f.nameIndex,
            numArgs = f.numArgs,
            ops = decoded,
            filePath = f.filePath,
            locations = f.locations,
        }
    end

    -- Resolve LOAD_GLOBAL targets to direct function references (saves a
    -- table lookup per call site in the interpreter).
    for i = 1, numFunctions do
        local ops = btc.functions[i].ops
        for j = 1, #ops do
            local op = ops[j]
            if op.k == OP_LOAD_GLOBAL then
                op.target = btc.functions[op.fi + 1]
            end
        end
    end

    local numExports = readU32(r)
    for _ = 1, numExports do
        local name = readString(r)
        local index = readU32(r)
        btc.exports[name] = index
    end

    local numPackages = readU32(r)
    for _ = 1, numPackages do
        local name = readString(r)
        btc.packages[name] = readI32(r)
    end

    return btc
end

Bytecode.SIGNATURE   = SIGNATURE
Bytecode.VERSION     = VERSION
Bytecode.PackedInt   = PackedInt
Bytecode.PackedFloat = PackedFloat

return Bytecode
