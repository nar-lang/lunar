-- Visualize a normalized AST as a tree of text lines.
-- Mirrors compiler.ast.parsed.tree_print so cross-implementation diffs are
-- trivial.

local M = {}

---@param offset integer
---@return string
local function indent(offset)
    return string.rep("\t", offset)
end

---@param v number
---@return string
local function formatFloat(v)
    for p = 1, 17 do
        local s = string.format("%." .. p .. "g", v)
        if tonumber(s) == v then
            return s
        end
    end
    return string.format("%.17g", v)
end

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

---@param list any[]|nil
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

---Format a normalized module. Definitions are emitted in their stored order
---(parsed order followed by any lifted lambdas). Dependencies are sorted by
---module name for stable diffs.
---@param module NormModule
---@param offset integer
---@return string
function M.moduleStringTree(module, offset)
    local buf = {
        indent(offset) .. string.format("NModule(name=%s)\n", formatName(module.name)),
    }
    ---@type QualifiedIdentifier[]
    local depKeys = {}
    for k in pairs(module.dependencies) do
        depKeys[#depKeys + 1] = k
    end
    table.sort(depKeys)
    for _, k in ipairs(depKeys) do
        local names = module.dependencies[k]
        local sorted = {}
        for _, n in ipairs(names) do
            sorted[#sorted + 1] = n
        end
        table.sort(sorted)
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "NDependency(module=%s, names=%s)\n",
            formatName(k), formatStringList(sorted))
    end
    appendChildren(buf, module.definitions, offset + 1)
    return table.concat(buf)
end

---@param node NormDefinition
---@param offset integer
handlers.NormDefinition = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "NDefinition(name=%s, hidden=%s)\n",
            formatName(node.name_), formatBool(node.hidden)),
    }
    appendChildren(buf, node.params_, offset + 1)
    if node.body_ ~= nil then
        buf[#buf + 1] = format(node.body_, offset + 1)
    end
    if node.declaredType ~= nil then
        buf[#buf + 1] = format(node.declaredType, offset + 1)
    end
    return table.concat(buf)
end

-- Expressions ---------------------------------------------------------------

---@param node NAccess
---@param offset integer
handlers.NAccess = function(node, offset)
    local buf = {
        indent(offset) .. string.format("NAccess(fieldName=%s)\n", formatName(node.fieldName)),
    }
    if node.record ~= nil then
        buf[#buf + 1] = format(node.record, offset + 1)
    end
    return table.concat(buf)
end

---@param node NApply
---@param offset integer
handlers.NApply = function(node, offset)
    local buf = { indent(offset) .. "NApply()\n" }
    if node.func ~= nil then
        buf[#buf + 1] = format(node.func, offset + 1)
    end
    appendChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node NCall
---@param offset integer
handlers.NCall = function(node, offset)
    local buf = {
        indent(offset) .. string.format("NCall(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node NConst
---@param offset integer
handlers.NConst = function(node, offset)
    return indent(offset) .. string.format("NConst(value=%s)\n", formatConst(node.value))
end

---@param node NConstructor
---@param offset integer
handlers.NConstructor = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "NConstructor(moduleName=%s, dataName=%s, optionName=%s)\n",
            formatName(node.moduleName), formatName(node.dataName), formatName(node.optionName)),
    }
    appendChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node NFunction
---@param offset integer
handlers.NFunction = function(node, offset)
    local buf = {
        indent(offset) .. string.format("NFunction(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.params, offset + 1)
    if node.body ~= nil then
        buf[#buf + 1] = format(node.body, offset + 1)
    end
    if node.fnType ~= nil then
        buf[#buf + 1] = format(node.fnType, offset + 1)
    end
    if node.nested ~= nil then
        buf[#buf + 1] = format(node.nested, offset + 1)
    end
    return table.concat(buf)
end

---@param node NGlobal
---@param offset integer
handlers.NGlobal = function(node, offset)
    return indent(offset) .. string.format(
        "NGlobal(moduleName=%s, definitionName=%s)\n",
        formatName(node.moduleName), formatName(node.definitionName))
end

---@param node NLambda
---@param offset integer
handlers.NLambda = function(node, offset)
    local buf = { indent(offset) .. "NLambda()\n" }
    appendChildren(buf, node.params, offset + 1)
    if node.body ~= nil then
        buf[#buf + 1] = format(node.body, offset + 1)
    end
    return table.concat(buf)
end

---@param node NLet
---@param offset integer
handlers.NLet = function(node, offset)
    local buf = { indent(offset) .. "NLet()\n" }
    if node.pattern ~= nil then buf[#buf + 1] = format(node.pattern, offset + 1) end
    if node.value ~= nil then buf[#buf + 1] = format(node.value, offset + 1) end
    if node.nested ~= nil then buf[#buf + 1] = format(node.nested, offset + 1) end
    return table.concat(buf)
end

---@param node NList
---@param offset integer
handlers.NList = function(node, offset)
    local buf = { indent(offset) .. "NList()\n" }
    appendChildren(buf, node.items, offset + 1)
    return table.concat(buf)
end

---@param node NLocal
---@param offset integer
handlers.NLocal = function(node, offset)
    return indent(offset) .. string.format("NLocal(name=%s)\n", formatName(node.name))
end

---@param node NRecord
---@param offset integer
handlers.NRecord = function(node, offset)
    local buf = { indent(offset) .. "NRecord()\n" }
    for _, fld in ipairs(node.fields) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "NRecordField(name=%s)\n", formatName(fld.name))
        if fld.value ~= nil then
            buf[#buf + 1] = format(fld.value, offset + 2)
        end
    end
    return table.concat(buf)
end

---@param node NSelect
---@param offset integer
handlers.NSelect = function(node, offset)
    local buf = { indent(offset) .. "NSelect()\n" }
    if node.condition ~= nil then buf[#buf + 1] = format(node.condition, offset + 1) end
    for _, c in ipairs(node.cases) do
        buf[#buf + 1] = indent(offset + 1) .. "NSelectCase()\n"
        if c.pattern ~= nil then buf[#buf + 1] = format(c.pattern, offset + 2) end
        if c.expression ~= nil then buf[#buf + 1] = format(c.expression, offset + 2) end
    end
    return table.concat(buf)
end

---@param node NTuple
---@param offset integer
handlers.NTuple = function(node, offset)
    local buf = { indent(offset) .. "NTuple()\n" }
    appendChildren(buf, node.items, offset + 1)
    return table.concat(buf)
end

---@param node NUpdate
---@param offset integer
handlers.NUpdate = function(node, offset)
    local moduleStr
    if node.moduleName ~= nil and node.moduleName ~= "" then
        moduleStr = formatName(node.moduleName)
    else
        moduleStr = "<nil>"
    end
    local buf = {
        indent(offset) .. string.format(
            "NUpdate(moduleName=%s, recordName=%s)\n",
            moduleStr, formatName(node.recordName)),
    }
    for _, fld in ipairs(node.fields) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "NRecordField(name=%s)\n", formatName(fld.name))
        if fld.value ~= nil then
            buf[#buf + 1] = format(fld.value, offset + 2)
        end
    end
    return table.concat(buf)
end

-- Patterns ------------------------------------------------------------------

---@param buf string[]
---@param node NormPattern
---@param offset integer
local function appendDeclaredType(buf, node, offset)
    if node.declaredType ~= nil then
        buf[#buf + 1] = format(node.declaredType, offset)
    end
end

---@param node NPAlias
---@param offset integer
handlers.NPAlias = function(node, offset)
    local buf = {
        indent(offset) .. string.format("NPAlias(alias=%s)\n", formatName(node.alias)),
    }
    if node.nested ~= nil then buf[#buf + 1] = format(node.nested, offset + 1) end
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node NPAny
---@param offset integer
handlers.NPAny = function(node, offset)
    local buf = { indent(offset) .. "NPAny()\n" }
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node NPCons
---@param offset integer
handlers.NPCons = function(node, offset)
    local buf = { indent(offset) .. "NPCons()\n" }
    if node.head ~= nil then buf[#buf + 1] = format(node.head, offset + 1) end
    if node.tail ~= nil then buf[#buf + 1] = format(node.tail, offset + 1) end
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node NPConst
---@param offset integer
handlers.NPConst = function(node, offset)
    local buf = {
        indent(offset) .. string.format("NPConst(value=%s)\n", formatConst(node.value)),
    }
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node NPList
---@param offset integer
handlers.NPList = function(node, offset)
    local buf = { indent(offset) .. "NPList()\n" }
    appendChildren(buf, node.items, offset + 1)
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node NPNamed
---@param offset integer
handlers.NPNamed = function(node, offset)
    local buf = {
        indent(offset) .. string.format("NPNamed(name=%s)\n", formatName(node.name)),
    }
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node NPOption
---@param offset integer
handlers.NPOption = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "NPOption(moduleName=%s, definitionName=%s)\n",
            formatName(node.moduleName), formatName(node.definitionName)),
    }
    appendChildren(buf, node.values, offset + 1)
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node NPRecord
---@param offset integer
handlers.NPRecord = function(node, offset)
    local buf = { indent(offset) .. "NPRecord()\n" }
    for _, field in ipairs(node.fields) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "NPRecordField(name=%s)\n", formatName(field.name))
    end
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node NPTuple
---@param offset integer
handlers.NPTuple = function(node, offset)
    local buf = { indent(offset) .. "NPTuple()\n" }
    appendChildren(buf, node.items, offset + 1)
    appendDeclaredType(buf, node, offset + 1)
    return table.concat(buf)
end

-- Types ---------------------------------------------------------------------

---@param node NTData
---@param offset integer
handlers.NTData = function(node, offset)
    local buf = {
        indent(offset) .. string.format("NTData(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.args, offset + 1)
    for _, opt in ipairs(node.options) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "NDataOption(name=%s, hidden=%s)\n",
            formatName(opt.name), formatBool(opt.hidden))
        appendChildren(buf, opt.values, offset + 2)
    end
    return table.concat(buf)
end

---@param node NTFunc
---@param offset integer
handlers.NTFunc = function(node, offset)
    local buf = { indent(offset) .. "NTFunc()\n" }
    appendChildren(buf, node.params, offset + 1)
    if node.return_ ~= nil then
        buf[#buf + 1] = format(node.return_, offset + 1)
    end
    return table.concat(buf)
end

---@param node NTNative
---@param offset integer
handlers.NTNative = function(node, offset)
    local buf = {
        indent(offset) .. string.format("NTNative(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node NTParameter
---@param offset integer
handlers.NTParameter = function(node, offset)
    return indent(offset) .. string.format("NTParameter(name=%s)\n", formatName(node.name))
end

---@param node NTPlaceholder
---@param offset integer
handlers.NTPlaceholder = function(node, offset)
    return indent(offset) .. string.format("NTPlaceholder(name=%s)\n", formatName(node.name))
end

---@param node NTRecord
---@param offset integer
handlers.NTRecord = function(node, offset)
    local buf = { indent(offset) .. "NTRecord()\n" }
    local keys = {}
    for k in pairs(node.fields) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        buf[#buf + 1] = indent(offset + 1) .. string.format("NTRecordField(name=%s)\n", formatName(k))
        local ft = node.fields[k]
        if ft ~= nil then
            buf[#buf + 1] = format(ft, offset + 2)
        end
    end
    return table.concat(buf)
end

---@param node NTTuple
---@param offset integer
handlers.NTTuple = function(node, offset)
    local buf = { indent(offset) .. "NTTuple()\n" }
    appendChildren(buf, node.items, offset + 1)
    return table.concat(buf)
end

---@param node NTUnit
---@param offset integer
handlers.NTUnit = function(node, offset)
    return indent(offset) .. "NTUnit()\n"
end

---Format any normalized AST node as a tree.
---@param node NormStatement
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
