local SimpleAnything = require("lunar.compiler.ast.typed.simple_pattern").SimpleAnything
local SimpleLiteral = require("lunar.compiler.ast.typed.simple_pattern").SimpleLiteral
local SimpleConstructor = require("lunar.compiler.ast.typed.simple_pattern").SimpleConstructor

---@param p SimplePattern
---@return boolean
local function isAnything(p) return p.kind == "SimpleAnything" end
---@param p SimplePattern
---@return boolean
local function isLiteral(p) return p.kind == "SimpleLiteral" end
---@param p SimplePattern
---@return boolean
local function isCtor(p) return p.kind == "SimpleConstructor" end

---Repeat SimpleAnything n times.
---@param n integer
---@return SimplePattern[]
local function repeatAnything(n)
    local r = {}
    for i = 1, n do
        r[i] = SimpleAnything.new()
    end
    return r
end

---Append slice b to slice a (a[1..#a] then b[1..#b]). Returns new array.
---@param a any[]
---@param b any[]
---@return any[]
local function concat(a, b)
    local r = {}
    for i, v in ipairs(a) do r[i] = v end
    local n = #r
    for i, v in ipairs(b) do r[n + i] = v end
    return r
end

---Slice arr starting at `from` (1-based inclusive).
---@param arr any[]
---@param from integer
---@return any[]
local function tail(arr, from)
    local r = {}
    for i = from, #arr do
        r[#r + 1] = arr[i]
    end
    return r
end

---@param row SimplePattern[]
---@return SimplePattern[]|nil, boolean, string|nil
local function specializeRowByAnything(row)
    if #row == 0 then
        return nil, false, nil
    end
    local first = row[1]
    if isCtor(first) then
        return nil, false, nil
    elseif isAnything(first) then
        return tail(row, 2), true, nil
    elseif isLiteral(first) then
        return nil, false, nil
    end
    return nil, false, "impossible case"
end

---@param ctor TyDataOption
---@return fun(row: SimplePattern[]): SimplePattern[]|nil, boolean, string|nil
local function specializeRowByCtor(ctor)
    return function(row)
        if #row == 0 then
            return nil, false, "Empty matrices should not get specialized."
        end
        local first = row[1]
        if isCtor(first) then
            ---@cast first SimpleConstructor
            if first.name == ctor.name then
                return concat(first.args or {}, tail(row, 2)), true, nil
            else
                return nil, false, nil
            end
        elseif isAnything(first) then
            return concat(repeatAnything(#(ctor.values or {})), tail(row, 2)), true, nil
        elseif isLiteral(first) then
            return nil, false,
                "After type checking, constructors and literals should never align in pattern match exhaustiveness checks."
        end
        return nil, false, "impossible case"
    end
end

---@param literal SimpleLiteral
---@return fun(row: SimplePattern[]): SimplePattern[]|nil, boolean, string|nil
local function specializeRowByLiteral(literal)
    return function(row)
        if #row == 0 then
            return nil, false, "Empty matrices should not get specialized."
        end
        local first = row[1]
        if isCtor(first) then
            return nil, false,
                "After type checking, constructors and literals should never align in pattern match exhaustiveness checks."
        elseif isAnything(first) then
            return tail(row, 2), true, nil
        elseif isLiteral(first) then
            ---@cast first SimpleLiteral
            if first.literal:equals(literal.literal) then
                return tail(row, 2), true, nil
            else
                return nil, false, nil
            end
        end
        return nil, false, "impossible case"
    end
end

---Map a function f over array. f returns (value, keep, err). Result keeps
---values where keep=true. Aborts on err.
---@generic T, U
---@param f fun(x: T): U|nil, boolean, string|nil
---@param arr T[]
---@return U[]|nil, string|nil
local function mapIfError(f, arr)
    local out = {}
    for _, x in ipairs(arr) do
        local v, keep, err = f(x)
        if err ~= nil then
            return nil, err
        end
        if keep then
            out[#out + 1] = v
        end
    end
    return out, nil
end

---@param matrix SimplePattern[][]
---@return table<DataOptionIdentifier, TyData>|nil
local function collectCtors(matrix)
    ---@type table<DataOptionIdentifier, TyData>
    local ctors = {}
    for _, row in ipairs(matrix) do
        if row == nil then
            return nil
        end
        local first = row[1]
        if first ~= nil and isCtor(first) then
            ---@cast first SimpleConstructor
            ctors[first.name] = first.union
        end
    end
    return ctors
end

---@param ctors table<DataOptionIdentifier, TyData>
---@return TyData|nil
local function firstCtor(ctors)
    local keys = {}
    for k in pairs(ctors) do keys[#keys + 1] = k end
    if #keys == 0 then
        return nil
    end
    table.sort(keys)
    return ctors[keys[1]]
end

---@param matrix SimplePattern[][]
---@return TyDataOption[]|nil, boolean
local function isComplete(matrix)
    local ctors = collectCtors(matrix)
    if ctors == nil then
        return nil, false
    end
    local t = firstCtor(ctors)
    if t == nil then
        return nil, false
    end
    local numCtors = 0
    for _ in pairs(ctors) do numCtors = numCtors + 1 end
    if #t.options == numCtors then
        return t.options, true
    end
    return nil, false
end

---@param matrix SimplePattern[][]
---@param vector SimplePattern[]
---@return boolean, string|nil
local function isUseful(matrix, vector)
    if #matrix == 0 then
        return true, nil
    end
    if #vector == 0 then
        return false, nil
    end
    local first = vector[1]
    if isCtor(first) then
        ---@cast first SimpleConstructor
        local option, err = first:option()
        if err ~= nil then
            return false, err
        end
        ---@cast option -nil
        local patterns, perr = mapIfError(specializeRowByCtor(option), matrix)
        if perr ~= nil then
            return false, perr
        end
        ---@cast patterns -nil
        return isUseful(patterns, concat(first.args or {}, tail(vector, 2)))
    elseif isAnything(first) then
        local alts, ok = isComplete(matrix)
        if ok then
            ---@cast alts -nil
            for _, c in ipairs(alts) do
                local patterns, perr = mapIfError(specializeRowByCtor(c), matrix)
                if perr ~= nil then
                    return false, perr
                end
                ---@cast patterns -nil
                local useful, uerr = isUseful(patterns,
                    concat(repeatAnything(#(c.values or {})), tail(vector, 2)))
                if uerr ~= nil then
                    return false, uerr
                end
                ---@cast useful -nil
                if useful then
                    return true, nil
                end
            end
            return false, nil
        else
            local patterns, perr = mapIfError(specializeRowByAnything, matrix)
            if perr ~= nil then
                return false, perr
            end
            ---@cast patterns -nil
            return isUseful(patterns, tail(vector, 2))
        end
    elseif isLiteral(first) then
        ---@cast first SimpleLiteral
        local patterns, perr = mapIfError(specializeRowByLiteral(first), matrix)
        if perr ~= nil then
            return false, perr
        end
        ---@cast patterns -nil
        return isUseful(patterns, tail(vector, 2))
    end
    return false, "impossible case"
end

---@param patterns TypedPattern[]
---@return SimplePattern[][]|nil matrix
---@return TypedPattern[]|nil redundant
---@return string|nil err
local function toNonRedundantRows(patterns)
    ---@type SimplePattern[][]
    local matrix = {}
    ---@type TypedPattern[]
    local redundant = {}
    for _, pattern in ipairs(patterns) do
        local simplified = pattern:simplify()
        local row = { simplified }
        local useful, err = isUseful(matrix, row)
        if err ~= nil then
            return nil, nil, err
        end
        ---@cast useful -nil
        if useful then
            matrix[#matrix + 1] = row
        else
            redundant[#redundant + 1] = pattern
        end
    end
    return matrix, redundant, nil
end

---@param union TyData
---@param ctors table<DataOptionIdentifier, TyData>
---@return fun(alt: TyDataOption): SimplePattern|nil, boolean
local function isMissing(union, ctors)
    return function(alt)
        if ctors[alt.name] ~= nil then
            return nil, false
        end
        return SimpleConstructor.new(union, alt.name, repeatAnything(#(alt.values or {}))), true
    end
end

---@param union TyData
---@param alt TyDataOption
---@param patterns SimplePattern[]
---@return SimplePattern[]
local function recoverCtor(union, alt, patterns)
    local n = #(alt.values or {})
    local args = {}
    for i = 1, n do args[i] = patterns[i] end
    local rest = {}
    for i = n + 1, #patterns do rest[#rest + 1] = patterns[i] end
    local result = { SimpleConstructor.new(union, alt.name, args) }
    for _, v in ipairs(rest) do result[#result + 1] = v end
    return result
end

---@param matrix SimplePattern[][]
---@param n integer
---@return SimplePattern[][], string|nil
local function isExhaustive(matrix, n)
    if #matrix == 0 then
        return { repeatAnything(n) }, nil
    end
    if n == 0 then
        return {}, nil
    end
    local ctors = collectCtors(matrix)
    local numSeen = 0
    if ctors ~= nil then
        for _ in pairs(ctors) do numSeen = numSeen + 1 end
    end
    if numSeen == 0 then
        local patterns, perr = mapIfError(specializeRowByAnything, matrix)
        if perr ~= nil then
            return {}, perr
        end
        ---@cast patterns -nil
        local exhaustive, eerr = isExhaustive(patterns, n - 1)
        if eerr ~= nil then
            return {}, eerr
        end
        ---@cast exhaustive -nil
        ---@type SimplePattern[][]
        local result = {}
        for _, row in ipairs(exhaustive) do
            ---@type SimplePattern[]
            local r = { SimpleAnything.new() }
            for _, v in ipairs(row) do r[#r + 1] = v end
            result[#result + 1] = r
        end
        return result, nil
    end
    ---@cast ctors -nil
    local alts = firstCtor(ctors)
    if alts == nil then
        return {}, "no constructors"
    end
    ---@cast alts TyData
    local altList = alts.options
    local numAlts = #altList
    if numSeen < numAlts then
        local patterns, perr = mapIfError(specializeRowByAnything, matrix)
        if perr ~= nil then
            return {}, perr
        end
        ---@cast patterns -nil
        local exhaustive, eerr = isExhaustive(patterns, n - 1)
        if eerr ~= nil then
            return {}, eerr
        end
        ---@cast exhaustive -nil
        local missing = isMissing(alts, ctors)
        ---@type SimplePattern[]
        local rest = {}
        for _, alt in ipairs(altList) do
            local p, keep = missing(alt)
            if keep then
                rest[#rest + 1] = p
            end
        end
        for i, row in ipairs(exhaustive) do
            if i <= #rest then
                local r = { rest[i] }
                for _, v in ipairs(row) do r[#r + 1] = v end
                exhaustive[i] = r
            end
        end
        local m = #rest
        if #exhaustive < m then
            m = #exhaustive
        end
        local trimmed = {}
        for i = 1, m do trimmed[i] = exhaustive[i] end
        return trimmed, nil
    else
        ---@type SimplePattern[][]
        local result = {}
        for _, alt in ipairs(altList) do
            local patterns, perr = mapIfError(specializeRowByCtor(alt), matrix)
            if perr ~= nil then
                return {}, perr
            end
            ---@cast patterns -nil
            local mx, mxerr = isExhaustive(patterns, #(alt.values or {}) + n - 1)
            if mxerr ~= nil then
                return {}, mxerr
            end
            ---@cast mx -nil
            for i, row in ipairs(mx) do
                local prefixed = recoverCtor(alts, alt, row)
                for _, v in ipairs(row) do prefixed[#prefixed + 1] = v end
                mx[i] = prefixed
            end
            for _, row in ipairs(mx) do
                result[#result + 1] = row
            end
        end
        return result, nil
    end
end

---@param patterns TypedPattern[]
---@return string|nil err
local function checkPatterns(patterns)
    local matrix, redundant, err = toNonRedundantRows(patterns)
    if err ~= nil then
        return err
    end
    ---@cast matrix -nil
    if #redundant > 0 then
        return "pattern matching is redundant"
    end
    local missingPatterns, eerr = isExhaustive(matrix, 1)
    if eerr ~= nil then
        return eerr
    end
    ---@cast missingPatterns -nil
    if #missingPatterns > 0 then
        local sb = { "pattern matching is not exhaustive, missing patterns: " }
        for _, p in ipairs(missingPatterns) do
            sb[#sb + 1] = "\n\t"
            for j, x in ipairs(p) do
                if j > 1 then
                    sb[#sb + 1] = ", "
                end
                sb[#sb + 1] = x:toString()
            end
            sb[#sb + 1] = ", "
        end
        return table.concat(sb)
    end
    return nil
end

---@param pattern TypedPattern
---@return string|nil err
local function checkPattern(pattern)
    return checkPatterns({ pattern })
end

return {
    checkPattern = checkPattern,
    checkPatterns = checkPatterns,
    isUseful = isUseful,
    isExhaustive = isExhaustive,
    isComplete = isComplete,
    collectCtors = collectCtors,
    firstCtor = firstCtor,
    isMissing = isMissing,
    recoverCtor = recoverCtor,
}
