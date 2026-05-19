local Location = require("compiler.ast.location").Location
local Const = require("compiler.ast.const")
local CUnit = Const.CUnit
local misc = require("compiler.ast.misc")

local typeData = require("compiler.ast.parsed.type_data")
local DataOption = typeData.DataOption
local TFunc = require("compiler.ast.parsed.type_func").TFunc
local TNamed = require("compiler.ast.parsed.type_named").TNamed
local TParameter = require("compiler.ast.parsed.type_parameter").TParameter
local TRecord = require("compiler.ast.parsed.type_record").TRecord
local TTuple = require("compiler.ast.parsed.type_tuple").TTuple
local TUnit = require("compiler.ast.parsed.type_unit").TUnit

local PAlias = require("compiler.ast.parsed.pattern_alias").PAlias
local PAny = require("compiler.ast.parsed.pattern_any").PAny
local PCons = require("compiler.ast.parsed.pattern_cons").PCons
local PConst = require("compiler.ast.parsed.pattern_const").PConst
local PList = require("compiler.ast.parsed.pattern_list").PList
local PNamed = require("compiler.ast.parsed.pattern_named").PNamed
local POption = require("compiler.ast.parsed.pattern_option").POption
local pRecordMod = require("compiler.ast.parsed.pattern_record")
local PRecord = pRecordMod.PRecord
local PRecordField = pRecordMod.PRecordField
local PTuple = require("compiler.ast.parsed.pattern_tuple").PTuple

local Access = require("compiler.ast.parsed.expression_access").Access
local Accessor = require("compiler.ast.parsed.expression_accessor").Accessor
local Apply = require("compiler.ast.parsed.expression_apply").Apply
local binOpMod = require("compiler.ast.parsed.expression_binOp")
local BinOp = binOpMod.BinOp
local BinOpItem = binOpMod.BinOpItem
local Call = require("compiler.ast.parsed.expression_call").Call
local ConstExpr = require("compiler.ast.parsed.expression_const").Const
local Function = require("compiler.ast.parsed.expression_function").Function
local If = require("compiler.ast.parsed.expression_if").If
local InfixVar = require("compiler.ast.parsed.expression_infixVar").InfixVar
local Lambda = require("compiler.ast.parsed.expression_lambda").Lambda
local Let = require("compiler.ast.parsed.expression_let").Let
local List = require("compiler.ast.parsed.expression_list").List
local Negate = require("compiler.ast.parsed.expression_negate").Negate
local recordExprMod = require("compiler.ast.parsed.expression_record")
local Record = recordExprMod.Record
local RecordField = recordExprMod.RecordField
local selectMod = require("compiler.ast.parsed.expression_select")
local Select = selectMod.Select
local SelectCase = selectMod.SelectCase
local Tuple = require("compiler.ast.parsed.expression_tuple").Tuple
local Update = require("compiler.ast.parsed.expression_update").Update
local Var = require("compiler.ast.parsed.expression_var").Var

local dataTypeMod = require("compiler.ast.parsed.dataType")
local DataType = dataTypeMod.DataType
local DataTypeOption = dataTypeMod.DataTypeOption
local DataTypeValue = dataTypeMod.DataTypeValue
local Definition = require("compiler.ast.parsed.definition").Definition
local Import = require("compiler.ast.parsed.import").Import
local infixMod = require("compiler.ast.parsed.infix")
local Infix = infixMod.Infix
local Associativity = infixMod.Associativity
local Alias = require("compiler.ast.parsed.alias").Alias
local Module = require("compiler.ast.parsed.module").Module

-- silence unused warnings; modules are part of the public surface
local _UNUSED = { CUnit, DataOption, TUnit, TRecord, TParameter, TTuple, TNamed, TFunc }

local Parser = {}

local constants = {
    kwModule = "module",
    kwImport = "import",
    kwAs = "as",
    kwExposing = "exposing",
    kwInfix = "infix",
    kwAlias = "alias",
    kwType = "type",
    kwDef = "def",
    kwHidden = "hidden",
    kwNative = "native",
    kwLeft = "left",
    kwRight = "right",
    kwNon = "non",
    kwIf = "if",
    kwThen = "then",
    kwElse = "else",
    kwLet = "let",
    kwIn = "in",
    kwSelect = "select",
    kwCase = "case",
    kwEnd = "end",

    seqComment = "//",
    seqCommentStart = "/*",
    seqCommentEnd = "*/",
    seqExposingAll = "*",
    seqParenthesisOpen = "(",
    seqParenthesisClose = ")",
    seqBracketsOpen = "[",
    seqBracketsClose = "]",
    seqBracesOpen = "{",
    seqBracesClose = "}",
    seqComma = ",",
    seqColon = ":",
    seqEqual = "=",
    seqBar = "|",
    seqUnderscore = "_",
    seqDot = ".",
    seqMinus = "-",
    seqLambda = "\\(",
    seqLambdaBind = "->",
    seqCaseBind = "->",
    seqInfixChars = "!#$%&*+-/:;<=>?^|~`",

    smbNewLine = "\n",
    smbQuoteString = '"',
    smbQuoteChar = "'",
    smbEscape = "\\",
}

Parser.keywords = {
    constants.kwModule,
    constants.kwImport,
    constants.kwAs,
    constants.kwExposing,
    constants.kwInfix,
    constants.kwAlias,
    constants.kwType,
    constants.kwDef,
    constants.kwHidden,
    constants.kwNative,
    constants.kwLeft,
    constants.kwRight,
    constants.kwNon,
    constants.kwIf,
    constants.kwThen,
    constants.kwElse,
    constants.kwLet,
    constants.kwIn,
    constants.kwSelect,
    constants.kwCase,
    constants.kwEnd,
}

---@class ParserSource
---@field filePath string
---@field cursor integer
---@field text string
---@field log any

---@param filePath string
---@param fileContent string
---@return table|nil module
---@return string[] errors
function Parser.parse(filePath, fileContent)
    local src = {
        filePath = filePath,
        cursor = 1,
        text = fileContent or "",
        log = nil,
    }
    return Parser.parseModule(src)
end

---@param src ParserSource
---@param start integer
---@return Location
function Parser.loc(src, start)
    local cursor = src.cursor
    if cursor <= 1 then
        return Location.new(src.filePath, src.text, 1, 1)
    end

    local finish = cursor - 1
    while finish > start do
        local ch = src.text:sub(finish, finish)
        if ch:match("%s") == nil then
            break
        end
        finish = finish - 1
    end

    return Location.new(src.filePath, src.text, start, finish + 1)
end

---@param src ParserSource
---@param msg string
---@return string
function Parser.newError(src, msg)
    return msg .. " at " .. src.filePath .. ":" .. tostring(src.cursor)
end

---@param src ParserSource
---@return boolean
function Parser.isOk(src)
    return src.cursor <= #src.text
end

---@param ch string
---@param first boolean
---@param qualified boolean
---@return boolean isIdent
---@return boolean nextFirst
function Parser.isIdentChar(ch, first, qualified)
    local wasFirst = first
    local nextFirst = false

    if ch:match("%a") then
        return true, nextFirst
    end

    if not wasFirst then
        if ch == "_" or ch == "`" or ch:match("%d") then
            return true, nextFirst
        end
        if qualified and ch == "." then
            nextFirst = true
            return true, nextFirst
        end
    end

    return false, nextFirst
end

---@param ch string
---@return boolean
function Parser.isInfixChar(ch)
    return constants.seqInfixChars:find(ch, 1, true) ~= nil
end

---@param src ParserSource
---@param value string
---@return string|nil
function Parser.readSequence(src, value)
    local start = src.cursor
    local finish = start + #value - 1

    if src.text:sub(start, finish) ~= value then
        src.cursor = start
        return nil
    end

    src.cursor = finish + 1
    return value
end

---@param src ParserSource
function Parser.skipWhiteSpace(src)
    while Parser.isOk(src) do
        local ch = src.text:sub(src.cursor, src.cursor)
        if ch:match("%s") == nil then
            break
        end
        src.cursor = src.cursor + 1
    end
end

---@param src ParserSource
function Parser.skipComment(src)
    if not Parser.isOk(src) then
        return
    end

    Parser.skipWhiteSpace(src)

    if Parser.readSequence(src, constants.seqComment) ~= nil then
        while Parser.isOk(src) and src.text:sub(src.cursor, src.cursor) ~= constants.smbNewLine do
            src.cursor = src.cursor + 1
        end
        if Parser.isOk(src) then
            src.cursor = src.cursor + 1
        end
    elseif Parser.readSequence(src, constants.seqCommentStart) ~= nil then
        local level = 1
        while Parser.isOk(src) do
            if Parser.readSequence(src, constants.seqCommentStart) ~= nil then
                level = level + 1
            elseif Parser.readSequence(src, constants.seqCommentEnd) ~= nil then
                level = level - 1
                if level == 0 then
                    break
                end
            end
            src.cursor = src.cursor + 1
        end
        if level ~= 0 then
            return
        end
    else
        return
    end

    Parser.skipWhiteSpace(src)
    Parser.skipComment(src)
end

---@param src ParserSource
---@param qualified boolean
---@return string|nil
function Parser.readIdentifier(src, qualified)
    local start = src.cursor
    local first = true

    while Parser.isOk(src) do
        local ch = src.text:sub(src.cursor, src.cursor)
        local ok, nextFirst = Parser.isIdentChar(ch, first, qualified)
        if not ok then
            break
        end
        src.cursor = src.cursor + 1
        first = nextFirst
    end

    if start ~= src.cursor then
        local value = src.text:sub(start, src.cursor - 1)
        Parser.skipComment(src)
        return value
    end

    src.cursor = start
    return nil
end

local numBin = { ["0"] = true, ["1"] = true }
local numOct = { ["0"] = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true, ["6"] = true, ["7"] = true }
local numDec = { ["0"] = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true, ["6"] = true, ["7"] = true, ["8"] = true, ["9"] = true }
local numHex = {
    ["0"] = true, ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true, ["6"] = true, ["7"] = true, ["8"] = true, ["9"] = true,
    ["a"] = true, ["b"] = true, ["c"] = true, ["d"] = true, ["e"] = true, ["f"] = true,
    ["A"] = true, ["B"] = true, ["C"] = true, ["D"] = true, ["E"] = true, ["F"] = true,
}

---@param src ParserSource
---@param allowBases boolean
---@return string value
---@return integer base
function Parser.readIntegerPart(src, allowBases)
    if not Parser.isOk(src) then
        return "", 0
    end

    local base = 10
    if allowBases then
        if Parser.readSequence(src, "0x") ~= nil or Parser.readSequence(src, "0X") ~= nil then
            base = 16
        elseif Parser.readSequence(src, "0b") ~= nil or Parser.readSequence(src, "0B") ~= nil then
            base = 2
        elseif Parser.readSequence(src, "0o") ~= nil or Parser.readSequence(src, "0O") ~= nil then
            base = 8
        end
    end

    local digits = (base == 2 and numBin) or (base == 8 and numOct) or (base == 16 and numHex) or numDec
    local out = {}

    while Parser.isOk(src) do
        local ch = src.text:sub(src.cursor, src.cursor)
        if not digits[ch] then
            break
        end
        out[#out + 1] = ch
        src.cursor = src.cursor + 1
    end

    return table.concat(out), base
end

---@param src ParserSource
---@return integer|nil
---@return string|nil
function Parser.parseInt(src)
    if not Parser.isOk(src) then
        return nil, nil
    end

    local pos = src.cursor
    local strValue, base = Parser.readIntegerPart(src, true)
    if strValue == "" then
        src.cursor = pos
        return nil, nil
    end

    local value = tonumber(strValue, base)
    if value == nil then
        return nil, Parser.newError(src, "failed to parse integer")
    end

    Parser.skipComment(src)
    return math.tointeger(value), nil
end

---@param src ParserSource
---@return number|nil
---@return string|nil
function Parser.parseFloat(src)
    if not Parser.isOk(src) then
        return nil, nil
    end

    local pos = src.cursor
    local first = Parser.readIntegerPart(src, false)
    if first == "" then
        return nil, nil
    end

    if Parser.readSequence(src, ".") ~= nil then
        local second = Parser.readIntegerPart(src, false)
        if second == "" then
            src.cursor = pos
            return nil, nil
        end
        first = first .. "." .. second
    end

    if Parser.readSequence(src, "e") ~= nil or Parser.readSequence(src, "E") ~= nil then
        local sign = ""
        if Parser.readSequence(src, "-") ~= nil then
            sign = "-"
        elseif Parser.readSequence(src, "+") ~= nil then
            sign = "+"
        end

        local second = Parser.readIntegerPart(src, false)
        if second == "" then
            src.cursor = pos
            return nil, nil
        end
        first = first .. "e" .. sign .. second
    end

    if Parser.isOk(src) then
        local ch = src.text:sub(src.cursor, src.cursor)
        if ch:match("[%a%d]") then
            src.cursor = pos
            return nil, nil
        end
    end

    Parser.skipComment(src)

    local value = tonumber(first)
    if value == nil then
        return nil, Parser.newError(src, "failed to parse float")
    end

    return value, nil
end

---@param src ParserSource
---@return boolean
function Parser.readExact(src, value)
    if Parser.readSequence(src, value) ~= nil then
        Parser.skipComment(src)
        return true
    end
    return false
end

local escapedChars = {
    ["0"] = "\0",
    ["a"] = "\a",
    ["b"] = "\b",
    ["f"] = "\f",
    ["n"] = "\n",
    ["r"] = "\r",
    ["t"] = "\t",
    ["v"] = "\v",
    ["\""] = "\"",
    ["'"] = "'",
    ["\\"] = "\\",
}

---@param src ParserSource
---@return string|nil
---@return string|nil
function Parser.parseChar(src)
    if not Parser.isOk(src) then
        return nil, nil
    end

    if src.text:sub(src.cursor, src.cursor) ~= constants.smbQuoteChar then
        return nil, nil
    end

    src.cursor = src.cursor + 1
    if not Parser.isOk(src) then
        return nil, Parser.newError(src, "character is not closed before end of file")
    end

    local current = src.text:sub(src.cursor, src.cursor)
    local value = nil
    local consumed = 1

    if current == constants.smbEscape then
        src.cursor = src.cursor + 1
        if not Parser.isOk(src) then
            return nil, Parser.newError(src, "character is not closed before end of file")
        end

        local esc = src.text:sub(src.cursor, src.cursor)
        local lowered = esc:lower()
        if lowered == "u" then
            src.cursor = src.cursor + 1
            local hex = src.text:sub(src.cursor, src.cursor + 3)
            if #hex ~= 4 or hex:match("^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") == nil then
                return nil, Parser.newError(src, "expected unicode character here")
            end
            local codepoint = tonumber(hex, 16)
            if codepoint == nil then
                return nil, Parser.newError(src, "failed to parse unicode character")
            end
            value = utf8.char(codepoint)
            src.cursor = src.cursor + 3
        else
            value = escapedChars[lowered] or escapedChars[esc]
            if value == nil then
                return nil, Parser.newError(src, "unknown escape sequence")
            end
        end
    else
        -- A Nar character literal contains exactly one Unicode codepoint;
        -- since src.text is a byte string, figure out how many bytes the
        -- UTF-8 encoding of the first codepoint occupies.
        local b = string.byte(current)
        if b < 0x80 then
            consumed = 1
        elseif b < 0xC0 then
            return nil, Parser.newError(src, "invalid UTF-8 sequence in character literal")
        elseif b < 0xE0 then
            consumed = 2
        elseif b < 0xF0 then
            consumed = 3
        else
            consumed = 4
        end
        value = src.text:sub(src.cursor, src.cursor + consumed - 1)
        if #value ~= consumed then
            return nil, Parser.newError(src, "truncated UTF-8 sequence in character literal")
        end
    end

    src.cursor = src.cursor + consumed
    if (not Parser.isOk(src)) or src.text:sub(src.cursor, src.cursor) ~= constants.smbQuoteChar then
        return nil, Parser.newError(src, "expected " .. constants.smbQuoteChar .. " here")
    end

    src.cursor = src.cursor + 1
    Parser.skipComment(src)
    return value, nil
end

---@param src ParserSource
---@return string|nil
---@return string|nil
function Parser.parseString(src)
    if not Parser.isOk(src) then
        return nil, nil
    end

    if src.text:sub(src.cursor, src.cursor) ~= constants.smbQuoteString then
        return nil, nil
    end

    src.cursor = src.cursor + 1
    local out = {}

    while Parser.isOk(src) do
        local ch = src.text:sub(src.cursor, src.cursor)
        if ch == constants.smbQuoteString then
            src.cursor = src.cursor + 1
            Parser.skipComment(src)
            return table.concat(out), nil
        end

        if ch == constants.smbEscape then
            src.cursor = src.cursor + 1
            if not Parser.isOk(src) then
                return nil, Parser.newError(src, "string is not closed before the end of file")
            end

            local esc = src.text:sub(src.cursor, src.cursor)
            local lowered = esc:lower()
            if lowered == "u" then
                local hex = src.text:sub(src.cursor + 1, src.cursor + 4)
                if #hex ~= 4 or hex:match("^[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]$") == nil then
                    return nil, Parser.newError(src, "expected unicode character here")
                end
                local codepoint = tonumber(hex, 16)
                if codepoint == nil then
                    return nil, Parser.newError(src, "failed to parse unicode character")
                end
                out[#out + 1] = utf8.char(codepoint)
                src.cursor = src.cursor + 4
            else
                local mapped = escapedChars[lowered] or escapedChars[esc]
                if mapped == nil then
                    return nil, Parser.newError(src, "unknown escape sequence")
                end
                out[#out + 1] = mapped
            end
        else
            out[#out + 1] = ch
        end

        src.cursor = src.cursor + 1
    end

    return nil, Parser.newError(src, "string is not closed before the end of file")
end

---@param src ParserSource
---@return integer|nil
---@return number|nil
---@return string|nil
function Parser.parseNumber(src)
    local pos = src.cursor
    local fValue, fErr = Parser.parseFloat(src)
    if fErr ~= nil then
        return nil, nil, fErr
    end
    local floatPos = src.cursor

    src.cursor = pos
    local iValue, iErr = Parser.parseInt(src)
    if iErr ~= nil then
        return nil, nil, iErr
    end

    if fValue == nil then
        return iValue, nil, nil
    end
    if iValue == nil then
        src.cursor = floatPos
        return nil, fValue, nil
    end

    if src.cursor ~= floatPos then
        src.cursor = floatPos
        return nil, fValue, nil
    end

    return iValue, nil, nil
end

---@param src ParserSource
---@return table|nil
---@return string|nil
function Parser.parseConst(src)
    local cValue, cErr = Parser.parseChar(src)
    if cErr ~= nil then
        return nil, cErr
    end
    if cValue ~= nil then
        return { kind = "CChar", value = cValue }, nil
    end

    local sValue, sErr = Parser.parseString(src)
    if sErr ~= nil then
        return nil, sErr
    end
    if sValue ~= nil then
        return { kind = "CString", value = sValue }, nil
    end

    local iValue, fValue, nErr = Parser.parseNumber(src)
    if nErr ~= nil then
        return nil, nErr
    end
    if fValue ~= nil then
        return { kind = "CFloat", value = fValue }, nil
    end
    if iValue ~= nil then
        return { kind = "CInt", value = iValue }, nil
    end

    return nil, nil
end

---@param src ParserSource
---@param withParenthesis boolean
---@return string|nil
function Parser.parseInfixIdentifier(src, withParenthesis)
    if not Parser.isOk(src) then
        return nil
    end

    local startCursor = src.cursor

    if withParenthesis and not Parser.readExact(src, constants.seqParenthesisOpen) then
        return nil
    end

    local start = src.cursor
    while Parser.isOk(src) and Parser.isInfixChar(src.text:sub(src.cursor, src.cursor)) do
        src.cursor = src.cursor + 1
    end
    local finish = src.cursor

    if finish == start then
        src.cursor = startCursor
        return nil
    end

    if withParenthesis and not Parser.readExact(src, constants.seqParenthesisClose) then
        src.cursor = startCursor
        return nil
    end

    local result = src.text:sub(start, finish - 1)
    Parser.skipComment(src)
    return result
end

---@param src ParserSource
---@return string[]|nil
---@return string|nil
function Parser.parseTypeParamNames(src)
    if not Parser.readExact(src, constants.seqBracketsOpen) then
        return nil, nil
    end

    local result = {}
    while true do
        local name = Parser.readIdentifier(src, false)
        if name == nil then
            return nil, Parser.newError(src, "expected variable type name here")
        end

        local first = name:sub(1, 1)
        if first:lower() ~= first then
            return nil, Parser.newError(src, "type parameter name should start with lowercase letter")
        end

        result[#result + 1] = name

        if Parser.readExact(src, constants.seqComma) then
            -- keep reading the next parameter
        elseif Parser.readExact(src, constants.seqBracketsClose) then
            break
        else
            return nil, Parser.newError(src, "expected ',' or ']' here")
        end
    end

    return result, nil
end

---@param src ParserSource
---@return Type|nil
---@return string|nil
function Parser.parseType(src)
    local cursor = src.cursor

    -- signature / tuple / unit
    if Parser.readExact(src, constants.seqParenthesisOpen) then
        if Parser.readExact(src, constants.seqParenthesisClose) then
            return TUnit.new(Parser.loc(src, cursor)), nil
        end

        local items = {}

        while true do
            local t, err = Parser.parseType(src)
            if err ~= nil then
                return nil, err
            end
            if t == nil then
                return nil, Parser.newError(src, "expected type here")
            end
            items[#items + 1] = t

            if Parser.readExact(src, constants.seqComma) then
                -- continue
            elseif Parser.readExact(src, constants.seqParenthesisClose) then
                break
            else
                return nil, Parser.newError(src, "expected `,` or `)` here")
            end
        end

        if Parser.readExact(src, constants.seqColon) then
            local ret, err = Parser.parseType(src)
            if err ~= nil then
                return nil, err
            end
            if ret == nil then
                return nil, Parser.newError(src, "expected return type here")
            end
            return TFunc.new(Parser.loc(src, cursor), items, ret), nil
        else
            if #items == 1 then
                return items[1], nil
            end
            return TTuple.new(Parser.loc(src, cursor), items), nil
        end
    end

    -- record
    if Parser.readExact(src, constants.seqBracesOpen) then
        local recCursor = src.cursor
        local ext = Parser.readIdentifier(src, true)
        if ext ~= nil and not Parser.readExact(src, constants.seqBar) then
            ext = nil
            src.cursor = recCursor
        end

        local fields = {}

        while true do
            local name = Parser.readIdentifier(src, false)
            if name == nil then
                return nil, Parser.newError(src, "expected field name here")
            end
            if not Parser.readExact(src, constants.seqColon) then
                return nil, Parser.newError(src, "expected `:` here")
            end
            local ft, err = Parser.parseType(src)
            if err ~= nil then
                return nil, err
            end
            if ft == nil then
                return nil, Parser.newError(src, "expected field type here")
            end

            if fields[name] ~= nil then
                return nil, Parser.newError(src,
                    "field with this name has already declared for the record")
            end
            fields[name] = ft

            if Parser.readExact(src, constants.seqComma) then
                -- continue
            elseif Parser.readExact(src, constants.seqBracesClose) then
                break
            else
                return nil, Parser.newError(src, "expected `,` or `}` here")
            end
        end

        return TRecord.new(Parser.loc(src, cursor), fields), nil
    end

    local nameStart = src.cursor
    local name = Parser.readIdentifier(src, true)
    if name ~= nil then
        local nameLocation = Parser.loc(src, nameStart)
        local firstCh = name:sub(1, 1)
        if firstCh:lower() == firstCh then
            return TParameter.new(Parser.loc(src, cursor), name), nil
        end

        local typeParams = {}
        if Parser.readExact(src, constants.seqBracketsOpen) then
            while true do
                local t, err = Parser.parseType(src)
                if err ~= nil then
                    return nil, err
                end
                if t == nil then
                    return nil, Parser.newError(src, "expected type parameter here")
                end
                typeParams[#typeParams + 1] = t

                if Parser.readExact(src, constants.seqComma) then
                    -- continue
                elseif Parser.readExact(src, constants.seqBracketsClose) then
                    break
                else
                    return nil, Parser.newError(src, "expected `,` or `]`  here")
                end
            end
        end

        return TNamed.new(Parser.loc(src, cursor), name, typeParams, nameLocation), nil
    end

    return nil, nil
end

---@param src ParserSource
---@return Pattern|nil
---@return string|nil
function Parser.parsePattern(src)
    local cursor = src.cursor

    -- tuple / unit
    if Parser.readExact(src, constants.seqParenthesisOpen) then
        if Parser.readExact(src, constants.seqParenthesisClose) then
            return Parser.finishParsePattern(src,
                PConst.new(Parser.loc(src, cursor), CUnit.new()))
        end
        local items = {}
        while true do
            local item, err = Parser.parsePattern(src)
            if err ~= nil then
                return nil, err
            end
            if item == nil then
                return nil, Parser.newError(src, "expected tuple item pattern here")
            end
            items[#items + 1] = item
            if Parser.readExact(src, constants.seqComma) then
                -- continue
            elseif Parser.readExact(src, constants.seqParenthesisClose) then
                break
            else
                return nil, Parser.newError(src, "expected `,` or `)` here")
            end
        end
        if #items == 1 then
            return Parser.finishParsePattern(src, items[1])
        end
        return Parser.finishParsePattern(src, PTuple.new(Parser.loc(src, cursor), items))
    end

    -- record
    if Parser.readExact(src, constants.seqBracesOpen) then
        local fields = {}
        while true do
            local fieldCursor = src.cursor
            local name = Parser.readIdentifier(src, false)
            if name == nil then
                return nil, Parser.newError(src, "expected record field name here")
            end
            fields[#fields + 1] = PRecordField.new(Parser.loc(src, fieldCursor), name)

            if Parser.readExact(src, constants.seqComma) then
                -- continue
            elseif Parser.readExact(src, constants.seqBracesClose) then
                break
            else
                return nil, Parser.newError(src, "expected `,` or `}` here")
            end
        end

        return Parser.finishParsePattern(src, PRecord.new(Parser.loc(src, cursor), fields))
    end

    -- list
    if Parser.readExact(src, constants.seqBracketsOpen) then
        if Parser.readExact(src, constants.seqBracketsClose) then
            return Parser.finishParsePattern(src, PList.new(Parser.loc(src, cursor), {}))
        end

        local items = {}
        while true do
            local p, err = Parser.parsePattern(src)
            if err ~= nil then
                return nil, err
            end
            if p == nil then
                return nil, Parser.newError(src, "expected list item pattern here")
            end
            items[#items + 1] = p
            if Parser.readExact(src, constants.seqComma) then
                -- continue
            elseif Parser.readExact(src, constants.seqBracketsClose) then
                break
            else
                return nil, Parser.newError(src, "expected `,` or `}` here")
            end
        end

        return Parser.finishParsePattern(src, PList.new(Parser.loc(src, cursor), items))
    end

    -- union / option
    local nameStart = src.cursor
    local name = Parser.readIdentifier(src, true)
    if name ~= nil and name:sub(1, 1):upper() == name:sub(1, 1) then
        local nameLocation = Parser.loc(src, nameStart)
        local items = {}
        if Parser.readExact(src, constants.seqParenthesisOpen) then
            while true do
                local item, err = Parser.parsePattern(src)
                if err ~= nil then
                    return nil, err
                end
                if item == nil then
                    return nil, Parser.newError(src, "expected option value pattern here")
                end
                items[#items + 1] = item
                if Parser.readExact(src, constants.seqComma) then
                    -- continue
                elseif Parser.readExact(src, constants.seqParenthesisClose) then
                    break
                else
                    return nil, Parser.newError(src, "expected `,` or `)` here")
                end
            end
        end
        return Parser.finishParsePattern(src,
            POption.new(Parser.loc(src, cursor), name, items, nameLocation))
    else
        src.cursor = cursor
    end

    nameStart = src.cursor
    name = Parser.readIdentifier(src, false)
    if name ~= nil and name:sub(1, 1):lower() == name:sub(1, 1) then
        local nameLocation = Parser.loc(src, nameStart)
        return Parser.finishParsePattern(src,
            PNamed.new(Parser.loc(src, cursor), name, nameLocation))
    else
        src.cursor = cursor
    end

    -- anything
    if Parser.readExact(src, constants.seqUnderscore) then
        return Parser.finishParsePattern(src, PAny.new(Parser.loc(src, cursor)))
    end

    local cValue, cErr = Parser.parseConst(src)
    if cErr ~= nil then
        return nil, cErr
    end
    if cValue ~= nil then
        return Parser.finishParsePattern(src,
            PConst.new(Parser.loc(src, cursor), cValue))
    end

    return nil, nil
end

---@param src ParserSource
---@param pat Pattern
---@return Pattern|nil
---@return string|nil
function Parser.finishParsePattern(src, pat)
    local cursor = src.cursor

    if Parser.readExact(src, constants.seqColon) then
        local t, err = Parser.parseType(src)
        if err ~= nil then
            return nil, err
        end
        if t == nil then
            return nil, Parser.newError(src, "expected type here")
        end
        pat.declaredType = t
        return Parser.finishParsePattern(src, pat)
    end

    if Parser.readExact(src, constants.kwAs) then
        local name = Parser.readIdentifier(src, false)
        if name == nil then
            return nil, Parser.newError(src, "expected pattern alias name here")
        end
        return Parser.finishParsePattern(src,
            PAlias.new(Parser.loc(src, cursor), name, pat))
    end

    if Parser.readExact(src, constants.seqBar) then
        local tail, err = Parser.parsePattern(src)
        if err ~= nil then
            return nil, err
        end
        if tail == nil then
            return nil, Parser.newError(src, "expected list tail pattern here")
        end
        return Parser.finishParsePattern(src,
            PCons.new(Parser.loc(src, cursor), pat, tail))
    end

    return pat, nil
end

---@param src ParserSource
---@return Pattern[]|nil
---@return Type|nil
---@return string|nil
function Parser.parseSignature(src)
    if not Parser.readExact(src, constants.seqParenthesisOpen) then
        return nil, nil, nil
    end

    local patterns = {}
    local ret = nil
    local err = nil

    while true do
        local pat, perr = Parser.parsePattern(src)
        if perr ~= nil then
            return nil, nil, perr
        end
        if pat == nil then
            return nil, nil, Parser.newError(src, "expected pattern here")
        end
        patterns[#patterns + 1] = pat

        if Parser.readExact(src, constants.seqComma) then
            -- continue
        elseif Parser.readExact(src, constants.seqParenthesisClose) then
            break
        else
            return nil, nil, Parser.newError(src, "expected `,` or `)` here")
        end
    end

    if Parser.readExact(src, constants.seqColon) then
        ret, err = Parser.parseType(src)
        if err ~= nil then
            return nil, nil, err
        end
        if ret == nil then
            return nil, nil, Parser.newError(src, "expected return type here")
        end
    end

    return patterns, ret, nil
end

---@param src ParserSource
---@param negate boolean
---@return Expression|nil
---@return string|nil
function Parser.parseExpression(src, negate)
    local cursor = src.cursor

    -- const
    local cValue, cErr = Parser.parseConst(src)
    if cErr ~= nil then
        return nil, cErr
    end
    if cValue ~= nil then
        return Parser.finishParseExpression(src,
            ConstExpr.new(Parser.loc(src, cursor), cValue), negate)
    end

    -- list
    if Parser.readExact(src, constants.seqBracketsOpen) then
        local items = {}
        if not Parser.readExact(src, constants.seqBracketsClose) then
            while true do
                local item, ierr = Parser.parseExpression(src, false)
                if ierr ~= nil then
                    return nil, ierr
                end
                if item == nil then
                    return nil, Parser.newError(src, "expected list item expression here")
                end
                items[#items + 1] = item

                if Parser.readExact(src, constants.seqComma) then
                    -- continue
                elseif Parser.readExact(src, constants.seqBracketsClose) then
                    break
                else
                    return nil, Parser.newError(src, "expected `,` or `]` here")
                end
            end
        end
        return Parser.finishParseExpression(src,
            List.new(Parser.loc(src, cursor), items), negate)
    end

    -- negate
    if Parser.readExact(src, constants.seqMinus) then
        return Parser.parseExpression(src, not negate)
    end

    -- infix value
    local infix = Parser.parseInfixIdentifier(src, true)
    if infix ~= nil then
        return Parser.finishParseExpression(src,
            InfixVar.new(Parser.loc(src, cursor), infix), negate)
    end

    -- lambda
    if Parser.readExact(src, constants.seqLambda) then
        src.cursor = cursor + 1

        local patterns, ret, perr = Parser.parseSignature(src)
        if perr ~= nil then
            return nil, perr
        end
        if patterns == nil then
            return nil, Parser.newError(src, "expected lambda signature here")
        end

        if not Parser.readExact(src, constants.seqLambdaBind) then
            return nil, Parser.newError(src, "expected `->` here")
        end

        local body, berr = Parser.parseExpression(src, false)
        if berr ~= nil then
            return nil, berr
        end
        if body == nil then
            return nil, Parser.newError(src, "expected lambda expression body here")
        end
        return Parser.finishParseExpression(src,
            Lambda.new(Parser.loc(src, cursor), patterns, ret, body), negate)
    end

    -- if
    if Parser.readExact(src, constants.kwIf) then
        local condition, cerr = Parser.parseExpression(src, false)
        if cerr ~= nil then
            return nil, cerr
        end
        if condition == nil then
            return nil, Parser.newError(src, "expected condition expression here")
        end
        if not Parser.readExact(src, constants.kwThen) then
            return nil, Parser.newError(src, "expected `then` here")
        end
        local positive, pperr = Parser.parseExpression(src, false)
        if pperr ~= nil then
            return nil, pperr
        end
        if positive == nil then
            return nil, Parser.newError(src, "expected positive branch expression here")
        end
        if not Parser.readExact(src, constants.kwElse) then
            return nil, Parser.newError(src, "expected `else` here")
        end
        local negative, nerr = Parser.parseExpression(src, false)
        if nerr ~= nil then
            return nil, nerr
        end
        if negative == nil then
            return nil, Parser.newError(src, "expected negative branch expression here")
        end
        return Parser.finishParseExpression(src,
            If.new(Parser.loc(src, cursor), condition, positive, negative), negate)
    end

    -- let
    if Parser.readExact(src, constants.kwLet) then
        local defCursor = src.cursor
        local name = Parser.readIdentifier(src, false)
        local nameLoc = Parser.loc(src, defCursor)
        local typeCursor = src.cursor
        local params, ret, serr = Parser.parseSignature(src)
        if serr ~= nil then
            return nil, serr
        end

        local pat = nil
        local value = nil
        local fnType = nil
        local isDef = name ~= nil and params ~= nil and #name > 0
            and name:sub(1, 1):lower() == name:sub(1, 1)
        if isDef then
            ---@cast name string
            ---@cast params Pattern[]
            if not Parser.readExact(src, constants.seqEqual) then
                return nil, Parser.newError(src, "expected `=` here")
            end
            local err
            value, err = Parser.parseExpression(src, false)
            if err ~= nil then
                return nil, err
            end
            if value == nil then
                return nil, Parser.newError(src, "expected function body here")
            end
            pat = PNamed.new(Parser.loc(src, defCursor), name, nameLoc)
            local paramTypes = {}
            for _, x in ipairs(params) do
                paramTypes[#paramTypes + 1] = x.declaredType
            end
            fnType = TFunc.new(Parser.loc(src, typeCursor), paramTypes, ret)
        else
            src.cursor = defCursor
            local perr
            pat, perr = Parser.parsePattern(src)
            if perr ~= nil then
                return nil, perr
            end
            if pat == nil then
                return nil, Parser.newError(src, "expected pattern here")
            end
            if not Parser.readExact(src, constants.seqEqual) then
                return nil, Parser.newError(src, "expected `=` here")
            end
            local verr
            value, verr = Parser.parseExpression(src, false)
            if verr ~= nil then
                return nil, verr
            end
            if value == nil then
                return nil, Parser.newError(src, "expected expression here")
            end
        end

        local preLet = src.cursor
        if Parser.readExact(src, constants.kwLet) then
            src.cursor = preLet
        elseif not Parser.readExact(src, constants.kwIn) then
            return nil, Parser.newError(src, "expected `let` or `in` here")
        end

        local nested, nerr = Parser.parseExpression(src, false)
        if nerr ~= nil then
            return nil, nerr
        end
        if nested == nil then
            return nil, Parser.newError(src, "expected expression here")
        end
        if isDef then
            ---@cast name string
            ---@cast params Pattern[]
            return Parser.finishParseExpression(src,
                Function.new(Parser.loc(src, cursor), name, nameLoc, params, value, fnType, nested),
                negate)
        end
        return Parser.finishParseExpression(src,
            Let.new(Parser.loc(src, cursor), pat, value, nested),
            negate)
    end

    -- select
    if Parser.readExact(src, constants.kwSelect) then
        local condition, cerr = Parser.parseExpression(src, false)
        if cerr ~= nil then
            return nil, cerr
        end
        if condition == nil then
            return nil, Parser.newError(src, "expected select condition expression here")
        end

        local cases = {}

        while true do
            local caseCursor = src.cursor
            if not Parser.readExact(src, constants.kwCase) then
                if not Parser.readExact(src, constants.kwEnd) then
                    return nil, Parser.newError(src, "expected `case` or `end` here")
                end
                break
            end

            local pat, perr = Parser.parsePattern(src)
            if perr ~= nil then
                return nil, perr
            end
            if pat == nil then
                return nil, Parser.newError(src, "expected pattern here")
            end

            if not Parser.readExact(src, constants.seqCaseBind) then
                return nil, Parser.newError(src, "expected `->` here")
            end

            local expr, eerr = Parser.parseExpression(src, false)
            if eerr ~= nil then
                return nil, eerr
            end
            if expr == nil then
                return nil, Parser.newError(src, "expected case expression here")
            end
            cases[#cases + 1] = SelectCase.new(Parser.loc(src, caseCursor), pat, expr)
        end

        if #cases == 0 then
            return nil, Parser.newError(src, "expected case expression here")
        end
        return Parser.finishParseExpression(src,
            Select.new(Parser.loc(src, cursor), condition, cases), negate)
    end

    -- accessor
    if Parser.readExact(src, constants.seqDot) then
        local name = Parser.readIdentifier(src, false)
        if name == nil then
            return nil, Parser.newError(src, "expected accessor name here")
        end
        return Parser.finishParseExpression(src,
            Accessor.new(Parser.loc(src, cursor), name), negate)
    end

    -- record / update
    if Parser.readExact(src, constants.seqBracesOpen) then
        if Parser.readExact(src, constants.seqBracesClose) then
            return Parser.finishParseExpression(src,
                Record.new(Parser.loc(src, cursor), {}), negate)
        end

        local recCursor = src.cursor

        local recName = Parser.readIdentifier(src, true)
        if recName ~= nil and not Parser.readExact(src, constants.seqBar) then
            src.cursor = recCursor
            recName = nil
        end

        local fields = {}
        while true do
            local fieldCursor = src.cursor

            local fieldName = Parser.readIdentifier(src, true)
            if fieldName == nil then
                return nil, Parser.newError(src, "expected field name here")
            end
            if not Parser.readExact(src, constants.seqEqual) then
                return nil, Parser.newError(src, "expected `=` here")
            end
            local expr, eerr = Parser.parseExpression(src, false)
            if eerr ~= nil then
                return nil, eerr
            end
            if expr == nil then
                return nil, Parser.newError(src, "expected record field value expression here")
            end
            fields[#fields + 1] = RecordField.new(Parser.loc(src, fieldCursor), fieldName, expr)

            if Parser.readExact(src, constants.seqComma) then
                -- continue
            elseif Parser.readExact(src, constants.seqBracesClose) then
                break
            else
                return nil, Parser.newError(src, "expected `,` or `}` here")
            end
        end

        if recName == nil then
            return Parser.finishParseExpression(src,
                Record.new(Parser.loc(src, cursor), fields), negate)
        end
        return Parser.finishParseExpression(src,
            Update.new(Parser.loc(src, cursor), recName, fields), negate)
    end

    -- tuple / void / precedence
    if Parser.readExact(src, constants.seqParenthesisOpen) then
        if Parser.readExact(src, constants.seqParenthesisClose) then
            return Parser.finishParseExpression(src,
                ConstExpr.new(Parser.loc(src, cursor), CUnit.new()), negate)
        end

        ---@type Expression[]
        local items = {}
        while true do
            local expr, eerr = Parser.parseExpression(src, false)
            if eerr ~= nil then
                return nil, eerr
            end
            if expr == nil then
                return nil, Parser.newError(src, "expected expression here")
            end
            items[#items + 1] = expr

            if Parser.readExact(src, constants.seqComma) then
                -- continue
            elseif Parser.readExact(src, constants.seqParenthesisClose) then
                break
            else
                return nil, Parser.newError(src, "expected `,` or `)` here")
            end
        end

        if #items == 1 then
            local expr = items[1]
            if expr.kind == "BinOp" then
                ---@cast expr BinOp
                expr:setInParentheses(true)
            end
            return Parser.finishParseExpression(src, expr, negate)
        end
        return Parser.finishParseExpression(src,
            Tuple.new(Parser.loc(src, cursor), items), negate)
    end

    local name = Parser.readIdentifier(src, true)
    if name ~= nil then
        return Parser.finishParseExpression(src,
            Var.new(Parser.loc(src, cursor), name), negate)
    end

    return nil, nil
end

---@param src ParserSource
---@param expr Expression
---@param negate boolean
---@return Expression|nil
---@return string|nil
function Parser.finishParseExpression(src, expr, negate)
    local cursor = src.cursor

    local infixOp = Parser.parseInfixIdentifier(src, false)
    if infixOp ~= nil then
        local final, err = Parser.parseExpression(src, false)
        if err ~= nil then
            return nil, err
        end
        if final == nil then
            return nil, Parser.newError(src,
                "expected second operand expression of binary expression here")
        end

        if negate then
            expr = Negate.new(Parser.loc(src, cursor), expr)
        end

        local items = {
            BinOpItem.newOperand(expr),
            BinOpItem.newFunc(infixOp),
        }

        local consumed = false
        if final.kind == "BinOp" then
            ---@cast final BinOp
            if not final:getInParentheses() then
                for _, it in ipairs(final:getItems()) do
                    items[#items + 1] = it
                end
                consumed = true
            end
        end
        if not consumed then
            items[#items + 1] = BinOpItem.newOperand(final)
        end

        return BinOp.new(Parser.loc(src, expr.location.start), items, false), nil
    end

    if Parser.readExact(src, constants.seqParenthesisOpen) then
        local items = {}
        while true do
            local item, ierr = Parser.parseExpression(src, false)
            if ierr ~= nil then
                return nil, ierr
            end
            if item == nil then
                return nil, Parser.newError(src, "expected function argument expression here")
            end
            items[#items + 1] = item

            if Parser.readExact(src, constants.seqComma) then
                -- continue
            elseif Parser.readExact(src, constants.seqParenthesisClose) then
                break
            else
                return nil, Parser.newError(src, "expected `,` or `)` here")
            end
        end
        return Parser.finishParseExpression(src,
            Apply.new(Parser.loc(src, expr.location.start), expr, items), negate)
    end

    if Parser.readExact(src, constants.seqDot) then
        local nameStart = src.cursor
        local name = Parser.readIdentifier(src, false)
        local nameLocation = Parser.loc(src, nameStart)
        if name == nil then
            return nil, Parser.newError(src, "expected field name here")
        end
        return Parser.finishParseExpression(src,
            Access.new(Parser.loc(src, cursor), expr, name, nameLocation), negate)
    end

    if negate then
        expr = Negate.new(Parser.loc(src, expr.location.start), expr)
    end
    return expr, nil
end

---@param src ParserSource
---@return DataTypeOption|nil
---@return string|nil
function Parser.parseDataOption(src)
    local cursor = src.cursor
    local hidden = Parser.readExact(src, constants.kwHidden)
    local types = {}

    local nameStart = src.cursor
    local name = Parser.readIdentifier(src, false)
    local nameLoc = Parser.loc(src, nameStart)

    if name == nil then
        return nil, Parser.newError(src, "expected option name here")
    end

    if Parser.readExact(src, constants.seqParenthesisOpen) then
        local index = 0
        while true do
            local argCursor = src.cursor
            local valueName = Parser.readIdentifier(src, false)
            if valueName == nil or not Parser.readExact(src, constants.seqColon) then
                src.cursor = argCursor
                valueName = string.format("p%d", index)
                index = index + 1
            end

            local t, err = Parser.parseType(src)
            if err ~= nil then
                return nil, err
            end
            if t == nil then
                return nil, Parser.newError(src, "expected option value type here")
            end
            types[#types + 1] = DataTypeValue.new(
                Parser.loc(src, argCursor), valueName, t, nameLoc)

            if Parser.readExact(src, constants.seqComma) then
                -- continue
            elseif Parser.readExact(src, constants.seqParenthesisClose) then
                break
            else
                return nil, Parser.newError(src, "expected `,` or `)`")
            end
        end
    end

    return DataTypeOption.new(
        Parser.loc(src, cursor), hidden, name, types, nameLoc), nil
end

---@param src ParserSource
---@return Import|nil
---@return string|nil
function Parser.parseImport(src)
    if not Parser.readExact(src, constants.kwImport) then
        return nil, nil
    end

    local cursor = src.cursor
    local exposingAll = false
    local alias = nil
    local exposing = {}
    local ident = Parser.readIdentifier(src, true)

    if ident == nil then
        return nil, Parser.newError(src, "expected module path string here")
    end

    if Parser.readExact(src, constants.kwAs) then
        alias = Parser.readIdentifier(src, false)
        if alias == nil then
            return nil, Parser.newError(src, "expected alias name here")
        end
    end

    if Parser.readExact(src, constants.kwExposing) then
        exposingAll = Parser.readExact(src, constants.seqExposingAll)
        if not exposingAll then
            if not Parser.readExact(src, constants.seqParenthesisOpen) then
                return nil, Parser.newError(src, "expected `(`")
            end

            while true do
                local id = Parser.readIdentifier(src, false)
                if id == nil then
                    local inf = Parser.parseInfixIdentifier(src, true)
                    if inf == nil then
                        return nil, Parser.newError(src,
                            "expected definition/infix name here")
                    end
                    exposing[#exposing + 1] = inf
                else
                    exposing[#exposing + 1] = id
                end

                if Parser.readExact(src, constants.seqComma) then
                    -- continue
                elseif Parser.readExact(src, constants.seqParenthesisClose) then
                    break
                else
                    return nil, Parser.newError(src, "expected `,` or `)`")
                end
            end
        end
    end

    return Import.new(Parser.loc(src, cursor), ident, alias, exposingAll, exposing), nil
end

---@param src ParserSource
---@return Infix|nil
---@return string|nil
function Parser.parseInfixFn(src)
    if not Parser.readExact(src, constants.kwInfix) then
        return nil, nil
    end
    local err = nil
    local cursor = src.cursor
    local hidden = Parser.readExact(src, constants.kwHidden)

    local name = nil
    local associativity = Associativity.NONE
    local precedence = 0
    local alias = nil
    local aliasCursor = src.cursor

    local pName = Parser.parseInfixIdentifier(src, true)
    if pName == nil then
        err = Parser.newError(src, "expected infix statement name here")
    end
    if err == nil then
        name = pName

        if not Parser.readExact(src, constants.seqColon) then
            err = Parser.newError(src, "expected `:` here")
        end
    end
    if err == nil then
        if not Parser.readExact(src, constants.seqParenthesisOpen) then
            err = Parser.newError(src, "expected `(` here")
        end
    end
    if err == nil then
        if Parser.readExact(src, constants.kwLeft) then
            associativity = Associativity.LEFT
        elseif Parser.readExact(src, constants.kwRight) then
            associativity = Associativity.RIGHT
        elseif Parser.readExact(src, constants.kwNon) then
            associativity = Associativity.NONE
        else
            err = Parser.newError(src, "expected `left`, `right` or `non` here")
        end
    end

    local pPrecedence = nil
    if err == nil then
        pPrecedence, err = Parser.parseInt(src)
    end
    if err == nil then
        if pPrecedence == nil then
            err = Parser.newError(src, "expected precedence (integer number) here")
        end
    end
    if err == nil then
        ---@cast pPrecedence integer
        precedence = pPrecedence
    end

    if err == nil then
        if not Parser.readExact(src, constants.seqParenthesisClose) then
            err = Parser.newError(src, "expected `)` here")
        end
    end

    if err == nil then
        if not Parser.readExact(src, constants.seqEqual) then
            err = Parser.newError(src, "expected `=` here")
        end
    end

    local pAlias = nil
    if err == nil then
        aliasCursor = src.cursor
        pAlias = Parser.readIdentifier(src, false)
    end
    if pAlias == nil and err == nil then
        err = Parser.newError(src, "expected definition name here")
    end
    if err == nil then
        alias = pAlias
    end

    return Infix.new(
        Parser.loc(src, cursor), hidden, name or "", associativity, precedence,
        Parser.loc(src, aliasCursor), alias or ""), err
end

---@param src ParserSource
---@return Alias|nil
---@return string|nil
function Parser.parseAlias(src)
    if not Parser.readExact(src, constants.kwAlias) then
        return nil, nil
    end

    local err = nil
    local cursor = src.cursor
    local hidden = Parser.readExact(src, constants.kwHidden)
    local native = Parser.readExact(src, constants.kwNative)
    local params = nil
    local t = nil
    local name = nil

    local nameStart = src.cursor
    local pName = Parser.readIdentifier(src, false)
    if pName == nil then
        err = Parser.newError(src, "expected alias name here")
    end
    local nameLoc = Parser.loc(src, nameStart)
    if err == nil then
        name = pName
    end

    if err == nil then
        params, err = Parser.parseTypeParamNames(src)
    end
    if err == nil then
        if not native then
            if not Parser.readExact(src, constants.seqEqual) then
                err = Parser.newError(src, "expected `=` here")
            end
            if err == nil then
                t, err = Parser.parseType(src)
            end
            if err == nil then
                if t == nil then
                    err = Parser.newError(src, "expected definedReturn declaration here")
                end
            end
        end
    end

    return Alias.new(Parser.loc(src, cursor), hidden, name or "", params or {}, t, nameLoc), err
end

---@param src ParserSource
---@return DataType|nil
---@return string|nil
function Parser.parseDataType(src)
    if not Parser.readExact(src, constants.kwType) then
        return nil, nil
    end

    local err = nil
    local cursor = src.cursor
    local hidden = Parser.readExact(src, constants.kwHidden)
    local name = nil
    local params = nil
    local options = {}

    local nameStart = src.cursor
    local pName = Parser.readIdentifier(src, false)
    local nameLoc = Parser.loc(src, nameStart)
    if pName == nil then
        err = Parser.newError(src, "expected data name here")
    end
    if err == nil then
        name = pName
    end

    params, err = Parser.parseTypeParamNames(src)
    if err == nil then
        if not Parser.readExact(src, constants.seqEqual) then
            err = Parser.newError(src, "expected `=` here")
        end
    end

    while err == nil do
        local option
        option, err = Parser.parseDataOption(src)
        if err == nil then
            options[#options + 1] = option
            if not Parser.readExact(src, constants.seqBar) then
                break
            end
        end
    end

    return DataType.new(Parser.loc(src, cursor), hidden, name or "", params or {}, options, nameLoc), err
end

---@param src ParserSource
---@param modName QualifiedIdentifier
---@return Definition|nil
---@return string|nil
function Parser.parseDefinition(src, modName)
    local cursor = src.cursor

    if not Parser.readExact(src, constants.kwDef) then
        return nil, nil
    end
    local hidden = Parser.readExact(src, constants.kwHidden)
    local native = Parser.readExact(src, constants.kwNative)

    local nameCursor = src.cursor
    local name = Parser.readIdentifier(src, false)
    local t = nil
    local body = nil

    if name == nil then
        return nil, Parser.newError(src, "expected data name here")
    end
    local nameLocation = Parser.loc(src, nameCursor)

    local typeCursor = src.cursor
    local params, ret, err = Parser.parseSignature(src)
    if err == nil then
        if params == nil then
            if Parser.readExact(src, constants.seqColon) then
                t, err = Parser.parseType(src)
                if err == nil and t == nil then
                    err = Parser.newError(src, "expected definedReturn here")
                end
            end
            if err == nil then
                if native then
                    body = Call.new(
                        Parser.loc(src, typeCursor),
                        misc.makeFullIdentifier(modName, name),
                        {})
                else
                    if not Parser.readExact(src, constants.seqEqual) then
                        err = Parser.newError(src, "expected `=` here")
                    end
                    if err == nil then
                        body, err = Parser.parseExpression(src, false)
                    end
                    if err == nil and body == nil then
                        err = Parser.newError(src, "expected expression here")
                    end
                end
            end
        else
            if native then
                local args = {}
                for _, x in ipairs(params) do
                    if x.kind == "PNamed" then
                        ---@cast x PNamed
                        args[#args + 1] = Var.new(x.location, x.name)
                    elseif x.kind ~= "PAny" then
                        err = Parser.newError(src,
                            "native function should start with lowercase letter and cannot be a pattern match")
                        break
                    end
                end
                if err == nil then
                    body = Call.new(
                        Parser.loc(src, typeCursor),
                        misc.makeFullIdentifier(modName, name),
                        args)
                end
            else
                if not Parser.readExact(src, constants.seqEqual) then
                    err = Parser.newError(src, "expected `=` here")
                end
                if err == nil then
                    body, err = Parser.parseExpression(src, false)
                end
                if err == nil and body == nil then
                    err = Parser.newError(src, "expected expression here")
                end
            end

            if err == nil then
                local anyTyped = false
                for _, x in ipairs(params) do
                    if x.declaredType ~= nil then
                        anyTyped = true
                        break
                    end
                end
                if ret ~= nil or anyTyped then
                    local paramTypes = {}
                    for _, x in ipairs(params) do
                        paramTypes[#paramTypes + 1] = x.declaredType
                    end
                    t = TFunc.new(Parser.loc(src, typeCursor), paramTypes, ret)
                end
            end
        end
    end

    return Definition.new(Parser.loc(src, cursor), hidden, name, nameLocation, params or {}, body, t), err
end

---@param src ParserSource
---@return Module|nil
---@return string[]
function Parser.parseModule(src)
    local errors = {}

    Parser.skipComment(src)

    if not Parser.readExact(src, constants.kwModule) then
        errors[#errors + 1] = Parser.newError(src, "expected `module` keyword here")
        return nil, errors
    end

    local name = Parser.readIdentifier(src, true)

    if name == nil then
        errors[#errors + 1] = Parser.newError(src, "expected module name here")
        return nil, errors
    end

    local imports = {}
    local aliases = {}
    local infixFns = {}
    local definitions = {}
    local dataTypes = {}

    while true do
        local imp, err = Parser.parseImport(src)
        if err ~= nil then
            errors[#errors + 1] = err
            Parser.skipToNextStatement(src)
        end
        if imp == nil then
            break
        end
        imports[#imports + 1] = imp
    end

    while true do
        local alias, err = Parser.parseAlias(src)
        if alias ~= nil then
            aliases[#aliases + 1] = alias
            if err == nil then
                goto continueLoop
            end
        end
        if err ~= nil then
            errors[#errors + 1] = err
            Parser.skipToNextStatement(src)
            goto continueLoop
        end

        local infixFn
        infixFn, err = Parser.parseInfixFn(src)
        if infixFn ~= nil then
            infixFns[#infixFns + 1] = infixFn
            if err == nil then
                goto continueLoop
            end
        end
        if err ~= nil then
            errors[#errors + 1] = err
            Parser.skipToNextStatement(src)
            goto continueLoop
        end

        local definition
        definition, err = Parser.parseDefinition(src, name)
        if definition ~= nil then
            definitions[#definitions + 1] = definition
            if err == nil then
                goto continueLoop
            end
        end
        if err ~= nil then
            errors[#errors + 1] = err
            Parser.skipToNextStatement(src)
            goto continueLoop
        end

        local dataType
        dataType, err = Parser.parseDataType(src)
        if dataType ~= nil then
            dataTypes[#dataTypes + 1] = dataType
            if err == nil then
                goto continueLoop
            end
        end
        if err ~= nil then
            errors[#errors + 1] = err
            Parser.skipToNextStatement(src)
            goto continueLoop
        end

        if Parser.isOk(src) then
            errors[#errors + 1] = Parser.newError(src, "failed to parse statement")
            if Parser.skipToNextStatement(src) then
                goto continueLoop
            end
        end
        break

        ::continueLoop::
    end

    return Module.new(name, Parser.loc(src, 1), imports, aliases, infixFns, definitions, dataTypes), errors
end

---@param src ParserSource
---@return boolean
function Parser.skipToNextStatement(src)
    while Parser.isOk(src) do
        src.cursor = src.cursor + 1
        local start = src.cursor

        if Parser.readExact(src, constants.kwAlias)
            or Parser.readExact(src, constants.kwDef)
            or Parser.readExact(src, constants.kwType)
            or Parser.readExact(src, constants.kwInfix)
            or Parser.readExact(src, constants.kwModule)
        then
            src.cursor = start
            return true
        end
    end
    return false
end

Parser.constants = constants

return Parser
