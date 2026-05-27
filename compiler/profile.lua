---Shared profiling helpers for the compiler pipeline.
---
---Stage timings live here so that `Compiler.compile` (in
---`lunar.compiler.init`) and individual AST passes (e.g. typed
---`module.lua` compose) can record into the same buckets without a
---cyclic require.
---
---Activation: set `LUNAR_PROFILE` to any non-empty value in the env,
---*or* set `Profile.enabled = true` before running `Compiler.compile`.
---When disabled, `wrap` is a no-op and helpers still work but no output
---is printed by the pipeline.

local Profile = {}

local _envProfile = (os.getenv and os.getenv("LUNAR_PROFILE")) or nil
Profile.enabled = (_envProfile ~= nil and _envProfile ~= "") and true or false

Profile.now = (function()
    local ok, socket = pcall(require, "socket")
    if ok and type(socket.gettime) == "function" then
        return socket.gettime
    end
    return os.clock
end)()

---@type table<string, table<string, number>>  -- stage -> key -> seconds
Profile.perKey = {}
---@type table<string, number>                  -- stage -> total seconds
Profile.stageTotal = {}

---Record a timing. `key` is typically a file name or module/definition.
---@param stage string
---@param key string
---@param dt number
function Profile.record(stage, key, dt)
    local s = Profile.perKey[stage]
    if s == nil then
        s = {}
        Profile.perKey[stage] = s
    end
    s[key] = (s[key] or 0) + dt
    Profile.stageTotal[stage] = (Profile.stageTotal[stage] or 0) + dt
end

function Profile.reset()
    Profile.perKey = {}
    Profile.stageTotal = {}
end

return Profile
