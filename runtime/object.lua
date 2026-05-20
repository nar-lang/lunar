---Object representation (runtime-2, optimized).
---
---Differences vs runtime/object.lua:
---  * Type identity is the object's metatable (not an `obj.kind` string).
---  * Tuples are flat arrays (no cons chain).
---  * Lists / records keep the cons-cell layout (needed for `::` and O(1)
---    record update).
---  * Empty sentinels are pre-allocated singletons (one per kind).
---  * Accessor functions still exist for use by natives; the interpreter
---    is expected to inline raw field reads on the hot path.
---
---Layouts:
---  UNIT     singleton {}                                  meta=M_UNIT
---  CHAR     {value=int}                                   meta=M_CHAR
---  INT      {value=int}                                   meta=M_INT
---  FLOAT    {value=number}                                meta=M_FLOAT
---  STRING   {value=string}                                meta=M_STRING
---  LIST     cons:   {value, next}                         meta=M_LIST
---           empty:  {} singleton                          meta=M_LIST_EMPTY
---  TUPLE    flat:   {n=N, [1..N]=item}                    meta=M_TUPLE
---  RECORD   field:  {key, value, parent}                  meta=M_RECORD
---           empty:  {} singleton                          meta=M_RECORD_EMPTY
---  OPTION   {name=string, values=array, n=integer}        meta=M_OPTION
---  FUNCTION {fn=function, arity=int}                      meta=M_FUNCTION
---  CLOSURE  {fnIndex=int, curried=array, n=int}           meta=M_CLOSURE
---  NATIVE   {ptr=any, cmp=function?}                      meta=M_NATIVE
---  PATTERN  {patKind=int, name=string, items=array, n=int} meta=M_PATTERN

local OK             = require("lunar.runtime.object_kind")

local Object         = {}

-- Per-kind metatables. Each carries __kind so getKind(obj) is one read.
local M_UNIT         = { __kind = OK.UNIT }
local M_CHAR         = { __kind = OK.CHAR }
local M_INT          = { __kind = OK.INT }
local M_FLOAT        = { __kind = OK.FLOAT }
local M_STRING       = { __kind = OK.STRING }
local M_LIST         = { __kind = OK.LIST }
local M_LIST_EMPTY   = { __kind = OK.LIST, __empty = true }
local M_TUPLE        = { __kind = OK.TUPLE }
local M_RECORD       = { __kind = OK.RECORD }
local M_RECORD_EMPTY = { __kind = OK.RECORD, __empty = true }
local M_OPTION       = { __kind = OK.OPTION }
local M_FUNCTION     = { __kind = OK.FUNCTION }
local M_CLOSURE      = { __kind = OK.CLOSURE }
local M_NATIVE       = { __kind = OK.NATIVE }
local M_PATTERN      = { __kind = OK.PATTERN }

Object.META          = {
    UNIT         = M_UNIT,
    CHAR         = M_CHAR,
    INT          = M_INT,
    FLOAT        = M_FLOAT,
    STRING       = M_STRING,
    LIST         = M_LIST,
    LIST_EMPTY   = M_LIST_EMPTY,
    TUPLE        = M_TUPLE,
    RECORD       = M_RECORD,
    RECORD_EMPTY = M_RECORD_EMPTY,
    OPTION       = M_OPTION,
    FUNCTION     = M_FUNCTION,
    CLOSURE      = M_CLOSURE,
    NATIVE       = M_NATIVE,
    PATTERN      = M_PATTERN,
}

local setmetatable   = setmetatable
local getmetatable   = getmetatable
local type           = type

-- ----------------------------------------------------------------------------
-- Generic
-- ----------------------------------------------------------------------------

---@param obj any
---@return integer kind 0 if not a runtime object
function Object.getKind(obj)
    if type(obj) ~= "table" then
        return OK.UNKNOWN
    end
    local m = getmetatable(obj)
    if m == nil then
        return OK.UNKNOWN
    end
    return m.__kind or OK.UNKNOWN
end

---@param obj any
---@return boolean
function Object.isValid(obj)
    if type(obj) ~= "table" then
        return false
    end
    local m = getmetatable(obj)
    return m ~= nil and m.__kind ~= nil
end

---Returns false for the empty-list / empty-record sentinels.
---@param obj any
---@return boolean
function Object.indexIsValid(obj)
    if type(obj) ~= "table" then
        return false
    end
    local m = getmetatable(obj)
    return m ~= nil and m.__kind ~= nil and m.__empty ~= true
end

local function expect(rt, obj, meta, kindName)
    if getmetatable(obj) ~= meta then
        rt:fail("expected object kind " .. kindName .. ", got " ..
            OK.name(Object.getKind(obj)))
        return false
    end
    return true
end

-- ----------------------------------------------------------------------------
-- Scalars
-- ----------------------------------------------------------------------------

local UNIT = setmetatable({}, M_UNIT)

function Object.makeUnit()
    return UNIT
end

function Object.toUnit(rt, obj)
    expect(rt, obj, M_UNIT, "unit")
end

function Object.makeChar(v)
    return setmetatable({ value = v }, M_CHAR)
end

function Object.toChar(rt, obj)
    if not expect(rt, obj, M_CHAR, "char") then return 0 end
    return obj.value
end

function Object.makeInt(v)
    return setmetatable({ value = v }, M_INT)
end

function Object.toInt(rt, obj)
    if not expect(rt, obj, M_INT, "int") then return 0 end
    return obj.value
end

function Object.makeFloat(v)
    return setmetatable({ value = v }, M_FLOAT)
end

function Object.toFloat(rt, obj)
    if not expect(rt, obj, M_FLOAT, "float") then return 0.0 end
    return obj.value
end

function Object.makeString(v)
    return setmetatable({ value = v }, M_STRING)
end

function Object.toString(rt, obj)
    if not expect(rt, obj, M_STRING, "string") then return "" end
    return obj.value
end

-- ----------------------------------------------------------------------------
-- Lists (cons cells)
-- ----------------------------------------------------------------------------

local EMPTY_LIST = setmetatable({}, M_LIST_EMPTY)

function Object.makeEmptyList()
    return EMPTY_LIST
end

function Object.makeListCons(head, tail)
    return setmetatable({ value = head, next = tail }, M_LIST)
end

---@param items table[] head-first
function Object.makeList(items)
    local first = EMPTY_LIST
    for i = #items, 1, -1 do
        first = setmetatable({ value = items[i], next = first }, M_LIST)
    end
    return first
end

function Object.toList(rt, obj)
    local m = getmetatable(obj)
    if m ~= M_LIST and m ~= M_LIST_EMPTY then
        rt:fail("expected list, got " .. OK.name(Object.getKind(obj)))
        return {}
    end
    local r, i = {}, 0
    while getmetatable(obj) == M_LIST do
        i = i + 1
        r[i] = obj.value
        obj = obj.next
    end
    return r
end

function Object.toListItem(rt, obj)
    if getmetatable(obj) ~= M_LIST then
        rt:fail("expected non-empty list")
        return UNIT, EMPTY_LIST
    end
    return obj.value, obj.next
end

-- ----------------------------------------------------------------------------
-- Tuples (flat array {n=N, [1..N]=item})
-- ----------------------------------------------------------------------------

---@param items table[]
function Object.makeTuple(items)
    local t = { n = #items }
    for i = 1, #items do t[i] = items[i] end
    return setmetatable(t, M_TUPLE)
end

function Object.toTuple(rt, obj)
    if getmetatable(obj) ~= M_TUPLE then
        rt:fail("expected tuple, got " .. OK.name(Object.getKind(obj)))
        return {}
    end
    local r, n = {}, obj.n
    for i = 1, n do r[i] = obj[i] end
    return r
end

-- ----------------------------------------------------------------------------
-- Records (cons cells with key/value/parent)
-- ----------------------------------------------------------------------------

local EMPTY_RECORD = setmetatable({}, M_RECORD_EMPTY)

function Object.makeEmptyRecord()
    return EMPTY_RECORD
end

function Object.makeRecordField(rt, record, key, value)
    local m = getmetatable(record)
    if m ~= M_RECORD and m ~= M_RECORD_EMPTY then
        rt:fail("expected record, got " .. OK.name(Object.getKind(record)))
        return EMPTY_RECORD
    end
    return setmetatable({ key = key, value = value, parent = record }, M_RECORD)
end

---@param rt Runtime
---@param keys string[]
---@param values table[]
function Object.makeRecord(rt, keys, values)
    local r = EMPTY_RECORD
    for i = 1, #keys do
        r = setmetatable({ key = keys[i], value = values[i], parent = r }, M_RECORD)
    end
    return r
end

---Build from an interleaved (value, key, value, key, ...) flat array.
---Mirrors OBJECT_KIND_RECORD layout from the bytecode.
---@param rt Runtime
---@param numFields integer
---@param items table[] length = numFields * 2
function Object.makeRecordRaw(rt, numFields, items)
    local r = EMPTY_RECORD
    for i = 2, numFields * 2, 2 do
        local keyObj = items[i]
        local k
        if type(keyObj) == "string" then
            k = keyObj
        elseif getmetatable(keyObj) == M_STRING then
            k = keyObj.value
        else
            k = Object.toString(rt, keyObj)
        end
        r = setmetatable({ key = k, value = items[i - 1], parent = r }, M_RECORD)
    end
    return r
end

function Object.toRecord(rt, obj)
    local m = getmetatable(obj)
    if m ~= M_RECORD and m ~= M_RECORD_EMPTY then
        rt:fail("expected record, got " .. OK.name(Object.getKind(obj)))
        return {}, {}
    end
    local seen, keys, values = {}, {}, {}
    local n = 0
    while getmetatable(obj) == M_RECORD do
        local k = obj.key
        if seen[k] == nil then
            seen[k] = true
            n = n + 1
            keys[n] = k
            values[n] = obj.value
        end
        obj = obj.parent
    end
    return keys, values
end

function Object.toRecordField(rt, obj, key)
    local m = getmetatable(obj)
    if m ~= M_RECORD and m ~= M_RECORD_EMPTY then
        rt:fail("expected record, got " .. OK.name(Object.getKind(obj)))
        return nil
    end
    while getmetatable(obj) == M_RECORD do
        if obj.key == key then
            return obj.value
        end
        obj = obj.parent
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- Options
-- ----------------------------------------------------------------------------

function Object.makeOption(name, values)
    local n = values and #values or 0
    return setmetatable({ name = name, values = values or {}, n = n }, M_OPTION)
end

function Object.toOption(rt, obj)
    if getmetatable(obj) ~= M_OPTION then
        rt:fail("expected option, got " .. OK.name(Object.getKind(obj)))
        return "", {}
    end
    return obj.name, obj.values
end

local BOOL_TRUE  = setmetatable({ name = OK.OPTION_NAME_TRUE, values = {}, n = 0 }, M_OPTION)
local BOOL_FALSE = setmetatable({ name = OK.OPTION_NAME_FALSE, values = {}, n = 0 }, M_OPTION)

function Object.makeBool(v)
    if v then return BOOL_TRUE end
    return BOOL_FALSE
end

function Object.toBool(rt, obj)
    if getmetatable(obj) ~= M_OPTION then
        rt:fail("expected Nar.Base.Basics.Bool option")
        return false
    end
    if obj == BOOL_TRUE or obj.name == OK.OPTION_NAME_TRUE then return true end
    if obj == BOOL_FALSE or obj.name == OK.OPTION_NAME_FALSE then return false end
    rt:fail("expected Nar.Base.Basics.Bool option")
    return false
end

-- ----------------------------------------------------------------------------
-- Functions / closures / natives
-- ----------------------------------------------------------------------------

function Object.makeFunc(fn, arity)
    return setmetatable({ fn = fn, arity = arity }, M_FUNCTION)
end

function Object.toFunc(rt, obj)
    if getmetatable(obj) ~= M_FUNCTION then
        rt:fail("expected function")
        return function() return UNIT end, 0
    end
    return obj.fn, obj.arity
end

function Object.makeClosure(fnIndex, curried)
    local n = curried and #curried or 0
    return setmetatable({ fnIndex = fnIndex, curried = curried or {}, n = n }, M_CLOSURE)
end

function Object.toClosure(rt, obj)
    if getmetatable(obj) ~= M_CLOSURE then
        rt:fail("expected closure")
        return -1, {}
    end
    return obj.fnIndex, obj.curried
end

function Object.makeNative(ptr, cmp)
    return setmetatable({ ptr = ptr, cmp = cmp }, M_NATIVE)
end

function Object.toNative(rt, obj)
    if getmetatable(obj) ~= M_NATIVE then
        rt:fail("expected native object")
        return nil, nil
    end
    return obj.ptr, obj.cmp
end

-- ----------------------------------------------------------------------------
-- Patterns
-- ----------------------------------------------------------------------------

function Object.makePattern(patKind, name, items)
    local n = items and #items or 0
    return setmetatable({ patKind = patKind, name = name or "", items = items or {}, n = n }, M_PATTERN)
end

function Object.toPattern(rt, obj)
    if getmetatable(obj) ~= M_PATTERN then
        rt:fail("expected pattern")
        return 0, "", {}
    end
    return obj.patKind, obj.name, obj.items
end

return Object
