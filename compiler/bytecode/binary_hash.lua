---BinaryHash mirrors nar-compiler/bytecode/binaryHash.go.

---@class BinaryHash
---@field funcsMap table<FullIdentifier, integer>  -- definition name -> index in binary.funcs
---@field stringMap table<string, integer>          -- string -> index in binary.strings
---@field constMap table<string, integer>           -- packed-const-key -> index in binary.consts
---@field compiledPaths QualifiedIdentifier[]
local BinaryHash = {}
BinaryHash.__index = BinaryHash

---@return BinaryHash
function BinaryHash.new()
    return setmetatable({
        funcsMap = {},
        stringMap = {},
        constMap = {},
        compiledPaths = {},
    }, BinaryHash)
end

---@param v string
---@param bin Binary
---@return integer hash
function BinaryHash:hashString(v, bin)
    local h = self.stringMap[v]
    if h ~= nil then
        return h
    end
    -- Go uses len(StringMap) (size of the dedup map) as the hash, which is
    -- equivalent to the current length of bin.strings (kept in sync because
    -- each new key appends exactly one string).
    local hash = #bin.strings
    self.stringMap[v] = hash
    bin.strings[#bin.strings + 1] = v
    return hash
end

---@param v PackedInt|PackedFloat
---@param bin Binary
---@return integer hash
function BinaryHash:hashConst(v, bin)
    local key = v:hashKey()
    local h = self.constMap[key]
    if h ~= nil then
        return h
    end
    local hash = #bin.consts
    self.constMap[key] = hash
    bin.consts[#bin.consts + 1] = v
    return hash
end

return { BinaryHash = BinaryHash }
