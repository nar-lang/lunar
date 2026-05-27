---Minimal JSON encoder / decoder for the LSP transport.
---
---Scope: handles the value subset produced and consumed by the LSP
---protocol (UTF-8 text, numbers as Lua numbers, booleans, arrays,
---objects). `Null` decodes to a distinguished sentinel (`Json.NULL`)
---so it round-trips through the encoder, but `nil` Lua values inside
---tables are encoded as missing keys.

local Json = {}

-- Sentinel for JSON `null`. Use `Json.NULL` to emit / detect null values.
Json.NULL = setmetatable({}, { __tostring = function() return "null" end })

-- Marker that forces an empty Lua table to encode as `[]` rather than `{}`.
Json.EMPTY_ARRAY = setmetatable({}, { __tostring = function() return "[]" end })

-- ----------------------------------------------------------------------------
-- Encoder
-- ----------------------------------------------------------------------------

local encodeValue

local ESCAPES = {
    ["\""] = "\\\"",
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
}

local function encodeString(s)
    local out = { '"' }
    for i = 1, #s do
        local c = s:sub(i, i)
        local b = string.byte(c)
        local esc = ESCAPES[c]
        if esc then
            out[#out + 1] = esc
        elseif b < 0x20 then
            out[#out + 1] = string.format("\\u%04x", b)
        else
            out[#out + 1] = c
        end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

local function encodeNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then
        error("cannot JSON-encode non-finite number")
    end
    if math.type(n) == "integer" then
        return tostring(n)
    end
    return string.format("%.17g", n)
end

---Decide whether `t` should encode as a JSON array or object.
---Treats a table as an array iff it has at least one positive integer
---key and every key is a positive integer in `1..n` with no holes.
local function isArray(t)
    if t == Json.EMPTY_ARRAY then return true end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" then return false end
        if k % 1 ~= 0 or k < 1 then return false end
        n = n + 1
    end
    return n == #t
end

local function encodeArray(t)
    if t == Json.EMPTY_ARRAY or #t == 0 then
        return "[]"
    end
    local out = { "[" }
    for i = 1, #t do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = encodeValue(t[i])
    end
    out[#out + 1] = "]"
    return table.concat(out)
end

local function encodeObject(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    if #keys == 0 then return "{}" end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    local out = { "{" }
    for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = encodeString(tostring(k))
        out[#out + 1] = ":"
        out[#out + 1] = encodeValue(t[k])
    end
    out[#out + 1] = "}"
    return table.concat(out)
end

encodeValue = function(v)
    if v == nil or v == Json.NULL then
        return "null"
    end
    local tv = type(v)
    if tv == "boolean" then
        return v and "true" or "false"
    elseif tv == "number" then
        return encodeNumber(v)
    elseif tv == "string" then
        return encodeString(v)
    elseif tv == "table" then
        if isArray(v) then
            return encodeArray(v)
        else
            return encodeObject(v)
        end
    end
    error("cannot JSON-encode value of type " .. tv)
end

---@param value any
---@return string
function Json.encode(value)
    return encodeValue(value)
end

-- ----------------------------------------------------------------------------
-- Decoder
-- ----------------------------------------------------------------------------

local decodeValue

local function decodeError(s, i, msg)
    error("JSON parse error at offset " .. i .. ": " .. msg)
end

local function skipWs(s, i)
    while i <= #s do
        local c = s:sub(i, i)
        if c == " " or c == "\t" or c == "\n" or c == "\r" then
            i = i + 1
        else
            return i
        end
    end
    return i
end

local function decodeString(s, i)
    if s:sub(i, i) ~= '"' then decodeError(s, i, "expected '\"'") end
    i = i + 1
    local out = {}
    while i <= #s do
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local e = s:sub(i + 1, i + 1)
            if e == '"' then out[#out + 1] = '"'; i = i + 2
            elseif e == "\\" then out[#out + 1] = "\\"; i = i + 2
            elseif e == "/" then out[#out + 1] = "/"; i = i + 2
            elseif e == "b" then out[#out + 1] = "\b"; i = i + 2
            elseif e == "f" then out[#out + 1] = "\f"; i = i + 2
            elseif e == "n" then out[#out + 1] = "\n"; i = i + 2
            elseif e == "r" then out[#out + 1] = "\r"; i = i + 2
            elseif e == "t" then out[#out + 1] = "\t"; i = i + 2
            elseif e == "u" then
                local hex = s:sub(i + 2, i + 5)
                local cp = tonumber(hex, 16)
                if cp == nil then decodeError(s, i, "bad \\u escape") end
                if cp < 0x80 then
                    out[#out + 1] = string.char(cp)
                elseif cp < 0x800 then
                    out[#out + 1] = string.char(
                        0xC0 | (cp >> 6),
                        0x80 | (cp & 0x3F))
                else
                    out[#out + 1] = string.char(
                        0xE0 | (cp >> 12),
                        0x80 | ((cp >> 6) & 0x3F),
                        0x80 | (cp & 0x3F))
                end
                i = i + 6
            else
                decodeError(s, i, "bad escape \\" .. (e or ""))
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
    decodeError(s, i, "unterminated string")
end

local function decodeNumber(s, i)
    local j = i
    if s:sub(j, j) == "-" then j = j + 1 end
    while j <= #s and s:sub(j, j):match("[0-9]") do j = j + 1 end
    if s:sub(j, j) == "." then
        j = j + 1
        while j <= #s and s:sub(j, j):match("[0-9]") do j = j + 1 end
    end
    local c = s:sub(j, j)
    if c == "e" or c == "E" then
        j = j + 1
        c = s:sub(j, j)
        if c == "+" or c == "-" then j = j + 1 end
        while j <= #s and s:sub(j, j):match("[0-9]") do j = j + 1 end
    end
    local raw = s:sub(i, j - 1)
    local n = tonumber(raw)
    if n == nil then decodeError(s, i, "bad number `" .. raw .. "`") end
    -- Prefer integer when possible.
    if raw:find("[.eE]") == nil and math.tointeger(n) ~= nil then
        n = math.tointeger(n)
    end
    return n, j
end

local function decodeLiteral(s, i, word, value)
    if s:sub(i, i + #word - 1) == word then
        return value, i + #word
    end
    decodeError(s, i, "expected literal `" .. word .. "`")
end

local function decodeArray(s, i)
    i = i + 1 -- consume `[`
    i = skipWs(s, i)
    local arr = {}
    if s:sub(i, i) == "]" then
        return arr, i + 1
    end
    while true do
        local v
        v, i = decodeValue(s, i)
        arr[#arr + 1] = (v == nil) and Json.NULL or v
        i = skipWs(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = skipWs(s, i + 1)
        elseif c == "]" then
            return arr, i + 1
        else
            decodeError(s, i, "expected `,` or `]` in array")
        end
    end
end

local function decodeObject(s, i)
    i = i + 1 -- consume `{`
    i = skipWs(s, i)
    local obj = {}
    if s:sub(i, i) == "}" then
        return obj, i + 1
    end
    while true do
        local key
        key, i = decodeString(s, i)
        i = skipWs(s, i)
        if s:sub(i, i) ~= ":" then
            decodeError(s, i, "expected `:` in object")
        end
        i = skipWs(s, i + 1)
        local v
        v, i = decodeValue(s, i)
        obj[key] = (v == nil) and Json.NULL or v
        i = skipWs(s, i)
        local c = s:sub(i, i)
        if c == "," then
            i = skipWs(s, i + 1)
        elseif c == "}" then
            return obj, i + 1
        else
            decodeError(s, i, "expected `,` or `}` in object")
        end
    end
end

decodeValue = function(s, i)
    i = skipWs(s, i)
    local c = s:sub(i, i)
    if c == '"' then return decodeString(s, i) end
    if c == "{" then return decodeObject(s, i) end
    if c == "[" then return decodeArray(s, i) end
    if c == "t" then return decodeLiteral(s, i, "true", true) end
    if c == "f" then return decodeLiteral(s, i, "false", false) end
    if c == "n" then return decodeLiteral(s, i, "null", Json.NULL) end
    if c == "-" or c:match("[0-9]") then return decodeNumber(s, i) end
    decodeError(s, i, "unexpected character `" .. c .. "`")
end

---@param s string
---@return any
function Json.decode(s)
    local v, _ = decodeValue(s, 1)
    return v
end

return Json
