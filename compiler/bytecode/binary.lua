---Binary blob writer/reader, mirrors nar-compiler/bytecode/binary.go byte-for-byte.

local op_mod = require("compiler.bytecode.op")
local const_hash = require("compiler.bytecode.const_hash")

local VERSION = 100
-- Same magic Go uses: 'N'<<8 | 'A'<<16 | 'R'<<24 == 0x52_41_4E_00.
local SIGNATURE = (string.byte("N") << 8)
    | (string.byte("A") << 16)
    | (string.byte("R") << 24)

---@class Func
---@field name StringHash
---@field numArgs integer
---@field ops integer[]
---@field filePath string
---@field locations integer[][]
local Func = {}
Func.__index = Func

---@param name StringHash
---@param numArgs integer
---@param ops integer[]
---@param filePath string
---@param locations integer[][]
---@return Func
function Func.new(name, numArgs, ops, filePath, locations)
    return setmetatable({
        name = name,
        numArgs = numArgs,
        ops = ops or {},
        filePath = filePath or "",
        locations = locations or {},
    }, Func)
end

---@class Binary
---@field compilerVersion integer
---@field funcs Func[]
---@field strings string[]
---@field consts (PackedInt|PackedFloat)[]
---@field exports table<FullIdentifier, Pointer>
---@field entry FullIdentifier
---@field packages table<QualifiedIdentifier, integer>
local Binary = {}
Binary.__index = Binary

---@return Binary
function Binary.new()
    return setmetatable({
        compilerVersion = 0,
        funcs = {},
        strings = {},
        consts = {},
        exports = {},
        entry = "",
        packages = {},
    }, Binary)
end

-- ----------------------------------------------------------------------------
-- Sorted iteration helpers (mirrors Go's slices.Sort for deterministic output)
-- ----------------------------------------------------------------------------

local function sortedKeys(map_)
    local keys = {}
    for k in pairs(map_) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

-- ----------------------------------------------------------------------------
-- Write
-- ----------------------------------------------------------------------------

---Serialize this Binary to a writer. The writer must have a :write(bytes)
---method (e.g. a file handle opened with `io.open(path, "wb")`).
---@param writer file*|table
---@param debug boolean
function Binary:write(writer, debug)
    local parts = {}

    local function w(fmt, ...)
        parts[#parts + 1] = string.pack(fmt, ...)
    end

    local function wbytes(s)
        parts[#parts + 1] = s
    end

    local function ws(s)
        w("<I4", #s)
        wbytes(s)
    end

    local function wbool(b)
        if b then
            w("<B", 1)
        else
            w("<B", 0)
        end
    end

    w("<I4", SIGNATURE)
    w("<I4", VERSION)
    w("<I4", self.compilerVersion)
    wbool(debug)
    ws(self.entry or "")

    w("<I4", #self.strings)
    for _, str in ipairs(self.strings) do
        ws(str)
    end

    w("<I4", #self.consts)
    for _, c in ipairs(self.consts) do
        local kind = c:kind()
        w("<B", kind)
        -- Go writes c.Pack() as uint64. For PackedInt we already have a
        -- signed integer with identical bit pattern; pack as <i8 to preserve
        -- negative values (uint64 cast is bitwise). For PackedFloat we have
        -- raw bits already (from string.unpack <I8).
        if kind == const_hash.KIND_FLOAT then
            w("<I8", c:pack())
        else
            w("<i8", c:pack())
        end
    end

    w("<I4", #self.funcs)
    for _, fn in ipairs(self.funcs) do
        w("<I4", fn.name)
        w("<I4", fn.numArgs)
        w("<I4", #fn.ops)
        for _, opWord in ipairs(fn.ops) do
            w("<I8", opWord)
        end
        if debug then
            ws(fn.filePath or "")
            for _, loc in ipairs(fn.locations) do
                w("<I4", loc[1])
                w("<I4", loc[2])
            end
        end
    end

    local exportNames = sortedKeys(self.exports)
    w("<I4", #exportNames)
    for _, n in ipairs(exportNames) do
        ws(n)
        w("<I4", self.exports[n])
    end

    local packageNames = sortedKeys(self.packages)
    w("<I4", #packageNames)
    for _, p in ipairs(packageNames) do
        ws(p)
        -- Go writes packages as int32; Lua int fits.
        w("<i4", self.packages[p])
    end

    writer:write(table.concat(parts))
end

return {
    Binary = Binary,
    Func = Func,
    VERSION = VERSION,
    SIGNATURE = SIGNATURE,
}
