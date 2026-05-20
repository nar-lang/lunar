---Bytecode interpreter (runtime-2, optimized).
---
---Key differences vs runtime/execute.lua:
---  * Ops are pre-decoded into records by bytecode.lua, so the hot loop
---    reads only `op.k`, `op.s`, `op.v`, etc. No bit-shifting, no string
---    table lookups, no per-op `lastError` polling.
---  * Errors throw Lua errors with a private sentinel table; `Runtime:apply`
---    catches them with a single outer `pcall`.
---  * Both stacks are tracked with manual `top` counters (no `#stack` per push/pop).
---  * Locals are stored in two parallel arrays (names + values) so no
---    `{name=…,value=…}` wrapper table is allocated per binding.
---  * Patterns produced by MAKE_PATTERN are memoized on the op record;
---    second-execution cost is one push.
---  * 0-arg global functions are memoized at the runtime level
---    (`rt.globalCache[fnTable] = result`), mirroring nar-runtime-js.
---  * Object accessors (`obj.value`, `obj.next`, …) are inlined directly.

local Op              = require("lunar.compiler.bytecode.op")
local Object          = require("lunar.runtime.object")
local OK              = require("lunar.runtime.object_kind")
local Errors          = require("lunar.runtime.errors")

local Execute         = {}

local throw           = Errors.throw

-- Local copies of all opcode / sub-kind constants (faster lookup).
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

local SK_OBJECT       = Op.STACK_KIND_OBJECT
local SK_PATTERN      = Op.STACK_KIND_PATTERN

local OBJK_LIST       = Op.OBJECT_KIND_LIST
local OBJK_TUPLE      = Op.OBJECT_KIND_TUPLE
local OBJK_RECORD     = Op.OBJECT_KIND_RECORD
local OBJK_OPTION     = Op.OBJECT_KIND_OPTION

local PK_ALIAS        = Op.PATTERN_KIND_ALIAS
local PK_ANY          = Op.PATTERN_KIND_ANY
local PK_CONS         = Op.PATTERN_KIND_CONS
local PK_CONST        = Op.PATTERN_KIND_CONST
local PK_DATA_OPTION  = Op.PATTERN_KIND_DATA_OPTION
local PK_LIST         = Op.PATTERN_KIND_LIST
local PK_NAMED        = Op.PATTERN_KIND_NAMED
local PK_RECORD       = Op.PATTERN_KIND_RECORD
local PK_TUPLE        = Op.PATTERN_KIND_TUPLE

local SPM_BOTH        = Op.SWAP_POP_MODE_BOTH
local SPM_POP         = Op.SWAP_POP_MODE_POP

local K_UNIT          = OK.UNIT
local K_CHAR          = OK.CHAR
local K_INT           = OK.INT
local K_FLOAT         = OK.FLOAT
local K_STRING        = OK.STRING
local K_RECORD        = OK.RECORD
local K_TUPLE         = OK.TUPLE
local K_LIST          = OK.LIST
local K_OPTION        = OK.OPTION
local K_PATTERN       = OK.PATTERN

local META            = Object.META
local M_LIST          = META.LIST
local M_LIST_EMPTY    = META.LIST_EMPTY
local M_RECORD        = META.RECORD
local M_RECORD_EMPTY  = META.RECORD_EMPTY
local M_TUPLE         = META.TUPLE
local M_OPTION        = META.OPTION
local M_PATTERN       = META.PATTERN
local M_STRING        = META.STRING
local M_CLOSURE       = META.CLOSURE

local makeUnit        = Object.makeUnit
local makeClosure     = Object.makeClosure
local makeList        = Object.makeList
local makeTuple       = Object.makeTuple
local makeRecordRaw   = Object.makeRecordRaw
local makeRecordField = Object.makeRecordField
local makeOption      = Object.makeOption
local makePattern     = Object.makePattern

local getmetatable    = getmetatable
local setmetatable    = setmetatable
local type            = type

-- ----------------------------------------------------------------------------
-- Const equality (for PATTERN_KIND_CONST)
-- ----------------------------------------------------------------------------

local function constEqualsTo(x, y)
    local mx = getmetatable(x)
    local my = getmetatable(y)
    if mx ~= my then
        throw("trying to compare objects of different types")
    end
    local k = mx and mx.__kind
    if k == K_UNIT then return true end
    if k == K_CHAR or k == K_INT or k == K_FLOAT or k == K_STRING then
        return x.value == y.value
    end
    throw("trying to compare objects of unsupported type")
    return false
end

-- ----------------------------------------------------------------------------
-- Pattern matching
-- ----------------------------------------------------------------------------

-- Forward decl
local match

---@param rt Runtime
---@param pattern table (PATTERN object)
---@param obj table
---@return boolean
function match(rt, pattern, obj)
    if getmetatable(pattern) ~= M_PATTERN then
        throw("expected pattern in match")
    end

    local patKind = pattern.patKind
    local name = pattern.name
    local items = pattern.items
    local n = pattern.n

    if patKind == PK_ALIAS then
        local names = rt.localNames
        local values = rt.localValues
        local lt = rt.localTop + 1
        rt.localTop = lt
        names[lt] = name
        values[lt] = obj
        if n ~= 1 then
            throw("alias pattern should have exactly one inner pattern")
        end
        return match(rt, items[1], obj)
    elseif patKind == PK_ANY then
        return true
    elseif patKind == PK_CONS then
        if n ~= 2 then
            throw("cons pattern should have exactly two inner patterns")
        end
        if getmetatable(obj) ~= M_LIST then
            return false
        end
        -- C ordering: items[2] (head pattern) first, then items[1] (tail pattern).
        if not match(rt, items[2], obj.value) then return false end
        return match(rt, items[1], obj.next)
    elseif patKind == PK_CONST then
        if n ~= 1 then
            throw("const pattern should have exactly one inner value")
        end
        return constEqualsTo(items[1], obj)
    elseif patKind == PK_DATA_OPTION then
        if getmetatable(obj) ~= M_OPTION then
            return false
        end
        if name ~= obj.name then return false end
        local optValues = obj.values
        if n ~= obj.n then
            throw("invalid option pattern match, number of values differs")
        end
        for i = 1, n do
            if not match(rt, items[i], optValues[i]) then return false end
        end
        return true
    elseif patKind == PK_LIST then
        local m = getmetatable(obj)
        if m ~= M_LIST and m ~= M_LIST_EMPTY then
            throw("expected list object in list pattern match")
        end
        -- Walk obj while comparing length to n.
        local len = 0
        local cur = obj
        while getmetatable(cur) == M_LIST do
            len = len + 1
            cur = cur.next
        end
        if len ~= n then return false end
        cur = obj
        for i = 1, n do
            if not match(rt, items[i], cur.value) then return false end
            cur = cur.next
        end
        return true
    elseif patKind == PK_NAMED then
        local lt = rt.localTop + 1
        rt.localTop = lt
        rt.localNames[lt] = name
        rt.localValues[lt] = obj
        return true
    elseif patKind == PK_RECORD then
        local names = rt.localNames
        local values = rt.localValues
        for i = 1, n do
            local nameObj = items[i]
            local fieldName
            if type(nameObj) == "string" then
                fieldName = nameObj
            elseif getmetatable(nameObj) == M_STRING then
                fieldName = nameObj.value
            else
                throw("record pattern item is not a string")
            end
            -- inline record-field lookup
            local rec = obj
            local rm = getmetatable(rec)
            if rm ~= M_RECORD and rm ~= M_RECORD_EMPTY then
                return false
            end
            local val
            while getmetatable(rec) == M_RECORD do
                if rec.key == fieldName then
                    val = rec.value
                    break
                end
                rec = rec.parent
            end
            if val == nil then return false end
            local lt = rt.localTop + 1
            rt.localTop = lt
            names[lt] = fieldName
            values[lt] = val
        end
        return true
    elseif patKind == PK_TUPLE then
        if getmetatable(obj) ~= M_TUPLE then return false end
        if obj.n ~= n then return false end
        for i = 1, n do
            if not match(rt, items[i], obj[i]) then return false end
        end
        return true
    end

    throw("loaded bytecode is corrupted (invalid pattern kind " .. tostring(patKind) .. ")")
    return false
end

Execute.match = match
Execute.constEqualsTo = constEqualsTo

-- ----------------------------------------------------------------------------
-- Main interpreter
-- ----------------------------------------------------------------------------

---@param rt Runtime
---@param fn RtFunc
---@param stack table[] initial args (also used as the working object stack)
---@return table result top-of-stack at function end
local function execute(rt, fn, stack)
    -- Push call frame
    local callTop = rt.callTop + 1
    rt.callTop = callTop
    rt.callStack[callTop] = fn.name

    -- Capture local-scope baseline for cleanup
    local baseLocalTop = rt.localTop

    -- Object stack: caller-provided args + slots used by this fn
    local top = #stack
    -- Pattern stack: function-local
    local patternStack = {}
    local pTop = 0

    local ops = fn.ops
    local numOps = #ops
    local index = 1

    while index <= numOps do
        local op = ops[index]
        local k = op.k

        if k == OP_LOAD_LOCAL then
            local lname = op.s
            local names = rt.localNames
            local values = rt.localValues
            local found = false
            local lt = rt.localTop
            for i = lt, baseLocalTop + 1, -1 do
                if names[i] == lname then
                    top = top + 1
                    stack[top] = values[i]
                    found = true
                    break
                end
            end
            if not found then
                throw("loaded bytecode is corrupted (undefined local '" .. tostring(lname) .. "')")
            end
        elseif k == OP_LOAD_GLOBAL then
            local glob = op.target
            if glob == nil then
                throw("loaded bytecode is corrupted (invalid function index " .. tostring(op.fi) .. ")")
            end
            ---@cast glob -nil
            if glob.numArgs == 0 then
                local cache = rt.globalCache
                local cached = cache[glob]
                if cached == nil then
                    cached = execute(rt, glob, {})
                    cache[glob] = cached
                end
                top = top + 1
                stack[top] = cached
            else
                top = top + 1
                stack[top] = makeClosure(op.fi, {})
            end
        elseif k == OP_LOAD_CONST then
            local v = op.v
            if v == nil then
                throw("loaded bytecode is corrupted (invalid const kind " .. tostring(op.c) .. ")")
            end
            if op.b == SK_OBJECT then
                top = top + 1
                stack[top] = v
            elseif op.b == SK_PATTERN then
                pTop = pTop + 1
                patternStack[pTop] = v
            else
                throw("loaded bytecode is corrupted (invalid stack kind " .. tostring(op.b) .. ")")
            end
        elseif k == OP_APPLY then
            local closureObj = stack[top]
            stack[top] = nil
            top = top - 1
            if getmetatable(closureObj) ~= M_CLOSURE then
                throw("expected closure in APPLY")
            end
            local fnIndex = closureObj.fnIndex
            local curried = closureObj.curried
            local cn = closureObj.n
            local numArgs = op.b

            -- Build args = curried ++ tail-of-stack
            local args = {}
            for i = 1, cn do args[i] = curried[i] end
            local baseIdx = top - numArgs
            for i = 1, numArgs do
                args[cn + i] = stack[baseIdx + i]
            end
            -- Pop applied args
            for i = top, baseIdx + 1, -1 do
                stack[i] = nil
            end
            top = baseIdx

            local f = rt.program.functions[fnIndex + 1]
            if f == nil then
                throw("loaded bytecode is corrupted (invalid function index " .. tostring(fnIndex) .. ")")
            end
            ---@cast f -nil
            local totalArgs = cn + numArgs
            local applyResult
            if f.numArgs == totalArgs then
                applyResult = execute(rt, f, args)
            elseif f.numArgs < totalArgs then
                -- Over-application: run with first numArgs, then re-apply the rest.
                local primary = {}
                for i = 1, f.numArgs do primary[i] = args[i] end
                local rest = {}
                for i = f.numArgs + 1, totalArgs do rest[i - f.numArgs] = args[i] end
                local partial = execute(rt, f, primary)
                applyResult = rt:applyFunc(partial, rest)
            else
                applyResult = makeClosure(fnIndex, args)
            end
            top = top + 1
            stack[top] = applyResult
        elseif k == OP_CALL then
            local name = op.s
            local def = rt.nativeDefs[name]
            if def == nil then
                throw("native implementation for definition `" .. name .. "` is not registered")
            end
            ---@cast def -nil
            local arity = def.arity
            -- CALL is only emitted as the entire body of a native-wrapper:
            -- consume the entire current stack.
            local n = top
            if arity ~= n then
                throw(string.format("definition `%s` arity mismatch (expected %d, got %d on stack)",
                    name, arity, n))
            end
            local args = {}
            for i = 1, n do
                args[i] = stack[i]
                stack[i] = nil
            end
            top = 0
            local callResult = def.fn(rt, table.unpack(args, 1, n))
            if not Object.isValid(callResult) then
                throw(string.format("definition `%s` returned invalid object", name))
            end
            top = top + 1
            stack[top] = callResult
        elseif k == OP_JUMP then
            if op.b == 0 then
                index = index + op.d
            else
                local pt = patternStack[pTop]
                patternStack[pTop] = nil
                pTop = pTop - 1
                local topObj = stack[top]
                if not match(rt, pt, topObj) then
                    if op.d == 0 then
                        throw("pattern match with jump delta 0 should not fail")
                    end
                    index = index + op.d
                end
            end
        elseif k == OP_MAKE_OBJECT then
            local b = op.b
            local a = op.a
            if b == OBJK_LIST then
                local items = {}
                local baseIdx = top - a
                for i = 1, a do items[i] = stack[baseIdx + i] end
                for i = top, baseIdx + 1, -1 do stack[i] = nil end
                top = baseIdx + 1
                stack[top] = makeList(items)
            elseif b == OBJK_TUPLE then
                local items = {}
                local baseIdx = top - a
                for i = 1, a do items[i] = stack[baseIdx + i] end
                for i = top, baseIdx + 1, -1 do stack[i] = nil end
                top = baseIdx + 1
                stack[top] = makeTuple(items)
            elseif b == OBJK_RECORD then
                local n = a * 2
                local items = {}
                local baseIdx = top - n
                for i = 1, n do items[i] = stack[baseIdx + i] end
                for i = top, baseIdx + 1, -1 do stack[i] = nil end
                top = baseIdx + 1
                stack[top] = makeRecordRaw(rt, a, items)
            elseif b == OBJK_OPTION then
                local nameObj = stack[top]
                stack[top] = nil
                top = top - 1
                local optName
                if getmetatable(nameObj) == M_STRING then
                    optName = nameObj.value
                elseif type(nameObj) == "string" then
                    optName = nameObj
                else
                    throw("option name is not a string")
                end
                local items = {}
                local baseIdx = top - a
                for i = 1, a do items[i] = stack[baseIdx + i] end
                for i = top, baseIdx + 1, -1 do stack[i] = nil end
                top = baseIdx + 1
                stack[top] = makeOption(optName, items)
            else
                throw("loaded bytecode is corrupted (invalid object kind " .. tostring(b) .. ")")
            end
        elseif k == OP_MAKE_PATTERN then
            local cached = op.cachedPattern
            if cached ~= nil then
                -- Pop the consumed items, push the cached pattern.
                local b = op.b
                local a = op.a
                local c = op.c
                local consume
                if b == PK_ALIAS then
                    consume = 1
                elseif b == PK_ANY or b == PK_NAMED then
                    consume = 0
                elseif b == PK_CONS then
                    consume = 2
                elseif b == PK_CONST then
                    consume = 1
                elseif b == PK_DATA_OPTION or b == PK_TUPLE then
                    consume = c
                elseif b == PK_LIST or b == PK_RECORD then
                    consume = a
                else
                    throw("loaded bytecode is corrupted (invalid pattern kind " .. tostring(b) .. ")")
                end
                for i = pTop, pTop - consume + 1, -1 do patternStack[i] = nil end
                pTop = pTop - consume
                pTop = pTop + 1
                patternStack[pTop] = cached
            else
                local b = op.b
                local a = op.a
                local c = op.c
                local pname = op.s or ""
                local consume

                if b == PK_ALIAS then
                    consume = 1
                elseif b == PK_ANY then
                    consume = 0
                elseif b == PK_CONS then
                    consume = 2
                elseif b == PK_CONST then
                    consume = 1
                elseif b == PK_DATA_OPTION then
                    consume = c
                elseif b == PK_LIST then
                    consume = a
                elseif b == PK_NAMED then
                    consume = 0
                elseif b == PK_RECORD then
                    consume = a
                elseif b == PK_TUPLE then
                    consume = c
                else
                    throw("loaded bytecode is corrupted (invalid pattern kind " .. tostring(b) .. ")")
                end

                local items = {}
                local baseIdx = pTop - consume
                for i = 1, consume do items[i] = patternStack[baseIdx + i] end
                for i = pTop, baseIdx + 1, -1 do patternStack[i] = nil end
                pTop = baseIdx

                local pat = makePattern(b, pname, items)
                op.cachedPattern = pat
                pTop = pTop + 1
                patternStack[pTop] = pat
            end
        elseif k == OP_ACCESS then
            local record = stack[top]
            local fieldName = op.s
            -- inline record-field lookup
            local rm = getmetatable(record)
            if rm ~= M_RECORD and rm ~= M_RECORD_EMPTY then
                throw("expected record in ACCESS, got " .. OK.name(Object.getKind(record)))
            end
            local val
            while getmetatable(record) == M_RECORD do
                if record.key == fieldName then
                    val = record.value
                    break
                end
                record = record.parent
            end
            if val == nil then
                throw("loaded bytecode is corrupted (record missing field '" .. fieldName .. "')")
            end
            stack[top] = val
        elseif k == OP_UPDATE then
            local key = op.s
            local value = stack[top]; stack[top] = nil; top = top - 1
            local rec = stack[top]
            stack[top] = makeRecordField(rt, rec, key, value)
        elseif k == OP_SWAP_POP then
            if op.b == SPM_BOTH then
                local v = stack[top]
                stack[top] = nil
                top = top - 1
                stack[top] = v
            elseif op.b == SPM_POP then
                stack[top] = nil
                top = top - 1
            else
                throw("loaded bytecode is corrupted (invalid swap pop kind " .. tostring(op.b) .. ")")
            end
        else
            throw("loaded binary is corrupted (invalid op kind " .. tostring(k) .. ")")
        end

        index = index + 1
    end

    if rt.localTop < baseLocalTop then
        throw("bytecode is corrupted (local stack underflow)")
    end

    -- Pop locals scoped to this frame
    local names, values = rt.localNames, rt.localValues
    for i = rt.localTop, baseLocalTop + 1, -1 do
        names[i] = nil
        values[i] = nil
    end
    rt.localTop = baseLocalTop

    -- Pop call frame
    rt.callStack[callTop] = nil
    rt.callTop = callTop - 1

    local result = stack[top]
    return result
end

Execute.execute = execute

return Execute
