-- Visualize a parsed AST as a tree of text lines.
-- One line per node, indented with `\t * offset`.
-- Children are printed with `offset + 1`.

local M = {}

---@param offset integer
---@return string
local function indent(offset)
    return string.rep("\t", offset)
end

---@param v number
---@return string
local function formatFloat(v)
    -- Match Go's strconv.FormatFloat(v, 'g', -1, 64): the shortest decimal
    -- representation that round-trips back to the same float64 value.
    for p = 1, 17 do
        local s = string.format("%." .. p .. "g", v)
        if tonumber(s) == v then
            return s
        end
    end
    return string.format("%.17g", v)
end

-- Quoting helper. Mirrors Go's strconv.Quote / fmt.Sprintf("%q", s):
--  * wraps with double quotes
--  * backslash-escapes "  \  \a \b \f \n \r \t \v
--  * other control bytes (< 0x20 or 0x7F) become \xNN
--  * non-ASCII bytes are emitted verbatim (valid UTF-8 round-trips)
local goQuoteEscapes = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\a"] = "\\a",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ["\v"] = "\\v",
}

---@param s string
---@return string
local function quoteString(s)
    local out = { '"' }
    for i = 1, #s do
        local ch = s:sub(i, i)
        local mapped = goQuoteEscapes[ch]
        if mapped ~= nil then
            out[#out + 1] = mapped
        else
            local b = string.byte(ch)
            if b < 0x20 or b == 0x7F then
                out[#out + 1] = string.format("\\x%02x", b)
            else
                out[#out + 1] = ch
            end
        end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

---@param v ConstValue|nil
---@return string
local function formatConst(v)
    if v == nil then
        return "nil"
    end
    local kind = v.kind
    if kind == "CInt" then
        return string.format("CInt(%d)", (v --[[@as CInt]]).value)
    elseif kind == "CFloat" then
        return string.format("CFloat(%s)", formatFloat((v --[[@as CFloat]]).value))
    elseif kind == "CString" then
        return string.format("CString(%s)", quoteString((v --[[@as CString]]).value))
    elseif kind == "CChar" then
        return string.format("CChar(%s)", quoteString((v --[[@as CChar]]).value))
    elseif kind == "CUnit" then
        return "CUnit"
    end
    return tostring(kind)
end

---@param assoc Associativity
---@return string
local function formatAssoc(assoc)
    if assoc == 1 then return "LEFT" end
    if assoc == 2 then return "RIGHT" end
    return "NONE"
end

---@param list any[]
---@return string
local function formatStringList(list)
    if list == nil or #list == 0 then
        return "[]"
    end
    return "[" .. table.concat(list, ", ") .. "]"
end

---@param b boolean|nil
---@return string
local function formatBool(b)
    if b then return "true" end
    return "false"
end

---@param name string|nil
---@return string
local function formatName(name)
    if name == nil or name == "" then
        return "<nil>"
    end
    return tostring(name)
end

---@param node any
---@param offset integer
---@return string
local function format(node, offset)
    if node == nil then
        return ""
    end
    return M.stringTree(node, offset)
end

---@param buf string[]
---@param children any[]|nil
---@param offset integer
local function appendChildren(buf, children, offset)
    if children == nil then
        return
    end
    for _, c in ipairs(children) do
        if c ~= nil then
            buf[#buf + 1] = M.stringTree(c, offset)
        end
    end
end

local handlers = {}

---@param node Module
---@param offset integer
handlers.Module = function(node, offset)
    local buf = {
        indent(offset) .. string.format("Module(name=%s)\n",
            formatName(node.name)),
    }
    appendChildren(buf, node.imports, offset + 1)
    appendChildren(buf, node.dataTypes, offset + 1)
    appendChildren(buf, node.aliases, offset + 1)
    appendChildren(buf, node.infixFns, offset + 1)
    appendChildren(buf, node.definitions, offset + 1)
    return table.concat(buf)
end

---@param node Import
---@param offset integer
handlers.Import = function(node, offset)
    return indent(offset) .. string.format(
        "Import(module=%s, alias=%s, exposingAll=%s, exposing=%s)\n",
        formatName(node.moduleIdentifier),
        formatName(node.alias),
        formatBool(node.exposingAll),
        formatStringList(node.exposing))
end

---@param node Alias
---@param offset integer
handlers.Alias = function(node, offset)
    local buf = {
        indent(offset) .. string.format("Alias(name=%s, hidden=%s, params=%s)\n",
            formatName(node.name), formatBool(node.hidden), formatStringList(node.params)),
    }
    if node.type ~= nil then
        buf[#buf + 1] = format(node.type, offset + 1)
    end
    return table.concat(buf)
end

---@param node Infix
---@param offset integer
handlers.Infix = function(node, offset)
    return indent(offset) .. string.format(
        "Infix(name=%s, hidden=%s, assoc=%s, precedence=%d, alias=%s)\n",
        formatName(node.name), formatBool(node.hidden),
        formatAssoc(node.associativity), node.precedence,
        formatName(node.alias))
end

---@param node DataType
---@param offset integer
handlers.DataType = function(node, offset)
    local buf = {
        indent(offset) .. string.format("DataType(name=%s, hidden=%s, params=%s)\n",
            formatName(node.name), formatBool(node.hidden), formatStringList(node.params)),
    }
    for _, opt in ipairs(node.options) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "DataTypeOption(name=%s, hidden=%s)\n",
            formatName(opt.name), formatBool(opt.hidden))
        for _, val in ipairs(opt.values) do
            buf[#buf + 1] = indent(offset + 2) .. string.format(
                "DataTypeValue(name=%s)\n", formatName(val.name))
            if val.type ~= nil then
                buf[#buf + 1] = format(val.type, offset + 3)
            end
        end
    end
    return table.concat(buf)
end

---@param node Definition
---@param offset integer
handlers.Definition = function(node, offset)
    local buf = {
        indent(offset) .. string.format("Definition(name=%s, hidden=%s)\n",
            formatName(node.name), formatBool(node.hidden)),
    }
    appendChildren(buf, node.params, offset + 1)
    if node.body ~= nil then
        buf[#buf + 1] = format(node.body, offset + 1)
    end
    if node.declaredType ~= nil then
        buf[#buf + 1] = format(node.declaredType, offset + 1)
    end
    return table.concat(buf)
end

-- Expressions ---------------------------------------------------------------

---@param node Access
---@param offset integer
handlers.Access = function(node, offset)
    local buf = {
        indent(offset) .. string.format("Access(fieldName=%s)\n", formatName(node.fieldName)),
    }
    if node.record ~= nil then
        buf[#buf + 1] = format(node.record, offset + 1)
    end
    return table.concat(buf)
end

---@param node Accessor
---@param offset integer
handlers.Accessor = function(node, offset)
    return indent(offset) .. string.format("Accessor(fieldName=%s)\n", formatName(node.fieldName))
end

---@param node Apply
---@param offset integer
handlers.Apply = function(node, offset)
    local buf = {
        indent(offset) .. "Apply()\n",
    }
    if node.func ~= nil then
        buf[#buf + 1] = format(node.func, offset + 1)
    end
    appendChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node BinOp
---@param offset integer
handlers.BinOp = function(node, offset)
    local buf = {
        indent(offset) .. string.format("BinOp(inParentheses=%s)\n", formatBool(node.inParentheses)),
    }
    for _, item in ipairs(node.items) do
        if item.operand ~= nil then
            buf[#buf + 1] = indent(offset + 1) .. "BinOpItem(operand)\n"
            buf[#buf + 1] = format(item.operand, offset + 2)
        elseif item.infix ~= nil then
            buf[#buf + 1] = indent(offset + 1) .. string.format(
                "BinOpItem(infix=%s)\n", formatName(item.infix))
        end
    end
    return table.concat(buf)
end

---@param node Call
---@param offset integer
handlers.Call = function(node, offset)
    local buf = {
        indent(offset) .. string.format("Call(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node Const
---@param offset integer
handlers.Const = function(node, offset)
    return indent(offset) .. string.format("Const(value=%s)\n", formatConst(node.value))
end

---@param node Constructor
---@param offset integer
handlers.Constructor = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "Constructor(moduleName=%s, dataName=%s, optionName=%s)\n",
            formatName(node.moduleName), formatName(node.dataName), formatName(node.optionName)),
    }
    appendChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node Function
---@param offset integer
handlers.Function = function(node, offset)
    local buf = {
        indent(offset) .. string.format("Function(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.params, offset + 1)
    if node.body ~= nil then
        buf[#buf + 1] = format(node.body, offset + 1)
    end
    if node.declaredType ~= nil then
        buf[#buf + 1] = format(node.declaredType, offset + 1)
    end
    if node.nested ~= nil then
        buf[#buf + 1] = format(node.nested, offset + 1)
    end
    return table.concat(buf)
end

---@param node If
---@param offset integer
handlers.If = function(node, offset)
    local buf = { indent(offset) .. "If()\n" }
    if node.condition ~= nil then buf[#buf + 1] = format(node.condition, offset + 1) end
    if node.positive ~= nil then buf[#buf + 1] = format(node.positive, offset + 1) end
    if node.negative ~= nil then buf[#buf + 1] = format(node.negative, offset + 1) end
    return table.concat(buf)
end

---@param node InfixVar
---@param offset integer
handlers.InfixVar = function(node, offset)
    return indent(offset) .. string.format("InfixVar(infix=%s)\n", formatName(node.infix))
end

---@param node Lambda
---@param offset integer
handlers.Lambda = function(node, offset)
    local buf = { indent(offset) .. "Lambda()\n" }
    appendChildren(buf, node.params, offset + 1)
    if node.returnType ~= nil then buf[#buf + 1] = format(node.returnType, offset + 1) end
    if node.body ~= nil then buf[#buf + 1] = format(node.body, offset + 1) end
    return table.concat(buf)
end

---@param node Let
---@param offset integer
handlers.Let = function(node, offset)
    local buf = { indent(offset) .. "Let()\n" }
    if node.pattern ~= nil then buf[#buf + 1] = format(node.pattern, offset + 1) end
    if node.value ~= nil then buf[#buf + 1] = format(node.value, offset + 1) end
    if node.nested ~= nil then buf[#buf + 1] = format(node.nested, offset + 1) end
    return table.concat(buf)
end

---@param node List
---@param offset integer
handlers.List = function(node, offset)
    local buf = { indent(offset) .. "List()\n" }
    appendChildren(buf, node.items, offset + 1)
    return table.concat(buf)
end

---@param node Negate
---@param offset integer
handlers.Negate = function(node, offset)
    local buf = { indent(offset) .. "Negate()\n" }
    if node.nested ~= nil then buf[#buf + 1] = format(node.nested, offset + 1) end
    return table.concat(buf)
end

---@param node Record
---@param offset integer
handlers.Record = function(node, offset)
    local buf = { indent(offset) .. "Record()\n" }
    for _, field in ipairs(node.fields) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "RecordField(name=%s)\n", formatName(field.name))
        if field.value ~= nil then
            buf[#buf + 1] = format(field.value, offset + 2)
        end
    end
    return table.concat(buf)
end

---@param node Select
---@param offset integer
handlers.Select = function(node, offset)
    local buf = { indent(offset) .. "Select()\n" }
    if node.condition ~= nil then buf[#buf + 1] = format(node.condition, offset + 1) end
    for _, c in ipairs(node.cases) do
        buf[#buf + 1] = indent(offset + 1) .. "SelectCase()\n"
        if c.pattern ~= nil then buf[#buf + 1] = format(c.pattern, offset + 2) end
        if c.body ~= nil then buf[#buf + 1] = format(c.body, offset + 2) end
    end
    return table.concat(buf)
end

---@param node Tuple
---@param offset integer
handlers.Tuple = function(node, offset)
    local buf = { indent(offset) .. "Tuple()\n" }
    appendChildren(buf, node.items, offset + 1)
    return table.concat(buf)
end

---@param node Update
---@param offset integer
handlers.Update = function(node, offset)
    local buf = {
        indent(offset) .. string.format("Update(recordName=%s)\n", formatName(node.recordName)),
    }
    for _, field in ipairs(node.fields) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "RecordField(name=%s)\n", formatName(field.name))
        if field.value ~= nil then
            buf[#buf + 1] = format(field.value, offset + 2)
        end
    end
    return table.concat(buf)
end

---@param node Var
---@param offset integer
handlers.Var = function(node, offset)
    return indent(offset) .. string.format("Var(name=%s)\n", formatName(node.name))
end

-- Patterns ------------------------------------------------------------------

local function appendDeclaredType(buf, node, offset)
    if node.declaredType ~= nil then
        buf[#buf + 1] = format(node.declaredType, offset)
    end
end

---@param node PAlias
---@param offset integer
handlers.PAlias = function(node, offset)
    local buf = {
        indent(offset) .. string.format("PAlias(alias=%s)\n", formatName(node.alias)),
    }
    if node.nested ~= nil then buf[#buf + 1] = format(node.nested, offset + 1) end
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node PAny
---@param offset integer
handlers.PAny = function(node, offset)
    local buf = { indent(offset) .. "PAny()\n" }
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node PCons
---@param offset integer
handlers.PCons = function(node, offset)
    local buf = { indent(offset) .. "PCons()\n" }
    if node.head ~= nil then buf[#buf + 1] = format(node.head, offset + 1) end
    if node.tail ~= nil then buf[#buf + 1] = format(node.tail, offset + 1) end
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node PConst
---@param offset integer
handlers.PConst = function(node, offset)
    local buf = {
        indent(offset) .. string.format("PConst(value=%s)\n", formatConst(node.value)),
    }
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node PList
---@param offset integer
handlers.PList = function(node, offset)
    local buf = { indent(offset) .. "PList()\n" }
    appendChildren(buf, node.items, offset + 1)
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node PNamed
---@param offset integer
handlers.PNamed = function(node, offset)
    local buf = {
        indent(offset) .. string.format("PNamed(name=%s)\n", formatName(node.name)),
    }
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node POption
---@param offset integer
handlers.POption = function(node, offset)
    local buf = {
        indent(offset) .. string.format("POption(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.args, offset + 1)
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node PRecord
---@param offset integer
handlers.PRecord = function(node, offset)
    local buf = { indent(offset) .. "PRecord()\n" }
    for _, field in ipairs(node.fields) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "PRecordField(name=%s)\n", formatName(field.name))
    end
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node PTuple
---@param offset integer
handlers.PTuple = function(node, offset)
    local buf = { indent(offset) .. "PTuple()\n" }
    appendChildren(buf, node.items, offset + 1)
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

-- Types ---------------------------------------------------------------------

---@param node TData
---@param offset integer
handlers.TData = function(node, offset)
    local buf = {
        indent(offset) .. string.format("TData(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.args, offset + 1)
    for _, opt in ipairs(node.options) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "DataOption(name=%s, hidden=%s)\n",
            formatName(opt.name), formatBool(opt.hidden))
        appendChildren(buf, opt.values, offset + 2)
    end
    return table.concat(buf)
end

---@param node TFunc
---@param offset integer
handlers.TFunc = function(node, offset)
    local buf = { indent(offset) .. "TFunc()\n" }
    appendChildren(buf, node.params, offset + 1)
    if node.return_ ~= nil then
        buf[#buf + 1] = format(node.return_, offset + 1)
    end
    return table.concat(buf)
end

---@param node TNamed
---@param offset integer
handlers.TNamed = function(node, offset)
    local buf = {
        indent(offset) .. string.format("TNamed(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node TNative
---@param offset integer
handlers.TNative = function(node, offset)
    local buf = {
        indent(offset) .. string.format("TNative(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node TParameter
---@param offset integer
handlers.TParameter = function(node, offset)
    return indent(offset) .. string.format("TParameter(name=%s)\n", formatName(node.name))
end

---@param node TRecord
---@param offset integer
handlers.TRecord = function(node, offset)
    local buf = { indent(offset) .. "TRecord()\n" }
    -- Sort keys for stable output across runs and across implementations.
    local keys = {}
    for k in pairs(node.fields) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        buf[#buf + 1] = indent(offset + 1) .. string.format("TRecordField(name=%s)\n", formatName(k))
        local ft = node.fields[k]
        if ft ~= nil then
            buf[#buf + 1] = format(ft, offset + 2)
        end
    end
    return table.concat(buf)
end

---@param node TTuple
---@param offset integer
handlers.TTuple = function(node, offset)
    local buf = { indent(offset) .. "TTuple()\n" }
    appendChildren(buf, node.items, offset + 1)
    return table.concat(buf)
end

---@param node TUnit
---@param offset integer
handlers.TUnit = function(node, offset)
    return indent(offset) .. "TUnit()\n"
end

---Format any parsed AST node as a tree.
---@param node Statement
---@param offset integer
---@return string
function M.stringTree(node, offset)
    if node == nil then
        return ""
    end
    local h = handlers[node.kind]
    if h ~= nil then
        return h(node, offset)
    end
    return indent(offset) .. string.format("?(%s)\n", tostring(node.kind))
end

return M
