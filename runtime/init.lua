---Nar runtime (optimized variant), Lua. Drop-in API-compatible with
---`require("runtime")`. Differences are internal: pre-decoded ops, manual
---stack tops, parallel locals arrays, single outer pcall, 0-arg global
---memoization, lazy pattern memoization.
---
---Usage:
---   local Runtime = require("runtime")
---   local btc = Runtime.loadBytecode(bytes)
---   local rt = Runtime.new(btc)
---   rt:registerDef("Some.Module", "nativeFn", function(rt, a, b) ... end, 2)
---   local result, err = rt:apply(rt:entry(), { rt:makeInt(42) })

local Bytecode   = require("runtime.bytecode")
local Object     = require("runtime.object")
local Runtime    = require("runtime.runtime")
local ObjectKind = require("runtime.object_kind")

---@param data string raw bytecode bytes
---@return RtBytecode
local function loadBytecode(data)
    return Bytecode.load(data)
end

return {
    new          = Runtime.new,
    loadBytecode = loadBytecode,
    Object       = Object,
    ObjectKind   = ObjectKind,
    Bytecode     = Bytecode,
    Runtime      = Runtime,
}
