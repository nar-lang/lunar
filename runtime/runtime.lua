---Runtime state + Apply/RegisterDef API (runtime-2, optimized).
---
---Same public surface as runtime/runtime.lua so it is a drop-in replacement.
---Internal differences:
---  * Parallel `localNames` + `localValues` arrays with a manual `localTop`,
---    so the executor never allocates per-binding wrapper tables.
---  * `callStack` is paired with a `callTop` counter for the same reason.
---  * `globalCache` memoizes 0-arg global definitions (mirrors nar-runtime-js).
---  * Errors are propagated via a tagged Lua error inside the interpreter
---    and caught by a single outer `pcall` here. `Runtime:fail(msg)` still
---    works for natives that want to abort cooperatively.

local Object     = require("lunar.runtime.object")
local Execute    = require("lunar.runtime.execute")
local Errors     = require("lunar.runtime.errors")

---@class Runtime
---@field program RtBytecode
---@field nativeDefs table<string, { fn: function, arity: integer }>
---@field localNames string[]
---@field localValues table[]
---@field localTop integer
---@field callStack string[]
---@field callTop integer
---@field globalCache table<table, table> memoized 0-arg globals
---@field metadata table<string, any>
---@field lastError string|nil
---@field stdoutFn fun(rt: Runtime, msg: string)
---@field _running boolean
local Runtime    = {}
Runtime.__index  = Runtime

local throw      = Errors.throw
local isOurError = Errors.isOurs

local function defaultStdout(_rt, msg)
    io.write(msg)
    io.write("\n")
end

---@param btc RtBytecode
---@return Runtime
function Runtime.new(btc)
    return setmetatable({
        program     = btc,
        nativeDefs  = {},
        localNames  = {},
        localValues = {},
        localTop    = 0,
        callStack   = {},
        callTop     = 0,
        globalCache = {},
        metadata    = {},
        lastError   = nil,
        stdoutFn    = defaultStdout,
        _running    = false,
    }, Runtime)
end

-- ----------------------------------------------------------------------------
-- Error / I/O
-- ----------------------------------------------------------------------------

---Records a fatal-style message and aborts the current run by raising a
---tagged Lua error caught by `apply()`. Safe to call from natives or from
---inside the interpreter.
---@param msg string
function Runtime:fail(msg)
    local parts = { tostring(msg), "\n" }
    for i = self.callTop, 1, -1 do
        parts[#parts + 1] = self.callStack[i]
        parts[#parts + 1] = "\n"
    end
    local withStack = table.concat(parts)
    if self.lastError ~= nil then
        self.lastError = self.lastError .. "\n----------------\n" .. tostring(msg)
    else
        self.lastError = withStack
    end
    throw(msg)
end

function Runtime:getError() return self.lastError end

function Runtime:clearError() self.lastError = nil end

function Runtime:setStdout(fn) self.stdoutFn = fn or defaultStdout end

function Runtime:print(msg) self.stdoutFn(self, msg) end

function Runtime:entry() return self.program.entry end

function Runtime:setMetadata(key, value) self.metadata[key] = value end

function Runtime:getMetadata(key) return self.metadata[key] end

-- ----------------------------------------------------------------------------
-- Native registration
-- ----------------------------------------------------------------------------

---@param moduleName string
---@param defName string
---@param fn fun(rt: Runtime, ...): table
---@param arity integer
function Runtime:registerDef(moduleName, defName, fn, arity)
    if type(fn) ~= "function" then
        error("registerDef: fn must be a function")
    end
    if type(arity) ~= "number" or arity < 0 then
        error("registerDef: arity must be a non-negative integer")
    end
    self.nativeDefs[moduleName .. "." .. defName] = { fn = fn, arity = arity }
end

-- ----------------------------------------------------------------------------
-- Apply
-- ----------------------------------------------------------------------------

---Apply a top-level export by its fully qualified name.
---@param name string
---@param args table[]|nil
---@return table|nil result, string|nil error
function Runtime:apply(name, args)
    if self._running then
        return nil, "runtime supports only single threaded execution"
    end
    local fnIndex = self.program.exports[name]
    if fnIndex == nil then
        return nil, "definition '" .. tostring(name) .. "' not exported in bytecode"
    end
    local closure = Object.makeClosure(fnIndex, {})
    self._running = true
    local ok, result = pcall(self.applyFunc, self, closure, args or {})
    self._running = false
    if ok then
        if self.lastError ~= nil then return nil, self.lastError end
        return result, nil
    end
    if isOurError(result) then
        ---@cast result table
        if self.lastError == nil then self.lastError = result.msg or tostring(result) end
        return nil, self.lastError
    end
    -- Raw Lua error from a buggy native.
    if self.lastError == nil then self.lastError = tostring(result) end
    return nil, self.lastError
end

---Apply an existing function/closure object. Raises on error; caller must
---catch via `apply()` or its own `pcall`.
---@param fnObj table closure object
---@param args table[]|nil
---@return table|nil
function Runtime:applyFunc(fnObj, args)
    args = args or {}
    if getmetatable(fnObj) ~= Object.META.CLOSURE then
        self:fail("applyFunc: expected closure")
        return nil
    end
    local fnIndex = fnObj.fnIndex
    local curried = fnObj.curried
    local cn = fnObj.n

    local allArgs = {}
    for i = 1, cn do allArgs[i] = curried[i] end
    for i = 1, #args do allArgs[cn + i] = args[i] end
    local numAll = #allArgs

    local f = self.program.functions[fnIndex + 1]
    if f == nil then
        self:fail("invalid function index " .. tostring(fnIndex))
        return nil
    end

    if numAll == f.numArgs then
        return Execute.execute(self, f, allArgs)
    elseif f.numArgs < numAll then
        local primary = {}
        for i = 1, f.numArgs do primary[i] = allArgs[i] end
        local rest = {}
        for i = f.numArgs + 1, numAll do rest[#rest + 1] = allArgs[i] end
        local result = Execute.execute(self, f, primary)
        return self:applyFunc(result, rest)
    else
        return Object.makeClosure(fnIndex, allArgs)
    end
end

-- Expose the error helpers so natives can interop if needed.
Runtime._ERR_TAG      = Errors.TAG
Runtime._throw        = throw
Runtime._isOurError   = isOurError

-- ----------------------------------------------------------------------------
-- Convenience: object constructors / accessors for natives.
-- ----------------------------------------------------------------------------

Runtime.makeUnit      = function(_self) return Object.makeUnit() end
Runtime.makeChar      = function(_self, v) return Object.makeChar(v) end
Runtime.makeInt       = function(_self, v) return Object.makeInt(v) end
Runtime.makeFloat     = function(_self, v) return Object.makeFloat(v) end
Runtime.makeString    = function(_self, v) return Object.makeString(v) end
Runtime.makeList      = function(_self, items) return Object.makeList(items) end
Runtime.makeListCons  = function(_self, h, t) return Object.makeListCons(h, t) end
Runtime.makeEmptyList = function(_self) return Object.makeEmptyList() end
Runtime.makeTuple     = function(_self, items) return Object.makeTuple(items) end
Runtime.makeRecord    = function(self, k, v) return Object.makeRecord(self, k, v) end
Runtime.makeOption    = function(_self, name, vs) return Object.makeOption(name, vs) end
Runtime.makeBool      = function(_self, v) return Object.makeBool(v) end
Runtime.makeFunc      = function(_self, fn, ar) return Object.makeFunc(fn, ar) end
Runtime.makeClosure   = function(_self, fi, cu) return Object.makeClosure(fi, cu) end
Runtime.makeNative    = function(_self, p, c) return Object.makeNative(p, c) end

Runtime.toChar        = function(self, o) return Object.toChar(self, o) end
Runtime.toInt         = function(self, o) return Object.toInt(self, o) end
Runtime.toFloat       = function(self, o) return Object.toFloat(self, o) end
Runtime.toString      = function(self, o) return Object.toString(self, o) end
Runtime.toList        = function(self, o) return Object.toList(self, o) end
Runtime.toTuple       = function(self, o) return Object.toTuple(self, o) end
Runtime.toRecord      = function(self, o) return Object.toRecord(self, o) end
Runtime.toRecordField = function(self, o, k) return Object.toRecordField(self, o, k) end
Runtime.toOption      = function(self, o) return Object.toOption(self, o) end
Runtime.toBool        = function(self, o) return Object.toBool(self, o) end
Runtime.toFunc        = function(self, o) return Object.toFunc(self, o) end
Runtime.toClosure     = function(self, o) return Object.toClosure(self, o) end
Runtime.toNative      = function(self, o) return Object.toNative(self, o) end

Runtime.objectKind    = function(_self, o) return Object.getKind(o) end
Runtime.objectIsValid = function(_self, o) return Object.isValid(o) end

return Runtime
