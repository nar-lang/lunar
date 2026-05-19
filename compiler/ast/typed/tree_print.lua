-- Visualize a typed AST as a tree of text lines.
-- Mirrors the normalized tree_print so cross-implementation diffs are
-- trivial: tab-indented, one node per line, headers `Ty*`/`T*`.
--
-- Notes:
--   - Each expression/pattern node prints its `type_` (inferred type) as a
--     "Type" child at the end of its body for full visibility into inference.
--   - Back-pointers (TyConstructor.dataType, TyGlobal/TyPOption.definition,
--     TyLocal/TyUpdate.target) are NOT recursed — only the identifying
--     fields on the node header are emitted.
--   - TUnbound is rendered as a single inline line; its `predecessor` chain
--     is intentionally NOT followed (it can be cyclic).

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

---Cycle guard used when descending into types. Types form a DAG (or worse,
---for recursive ADTs); keep a per-traversal visited set keyed by table
---identity so we never recurse twice into the same type node.
---@type table<table, true>|nil
local visitedTypes = nil

---@param node any
---@param offset integer
---@return string
local function formatType(node, offset)
    if node == nil then
        return ""
    end
    if visitedTypes == nil then
        visitedTypes = {}
    end
    if visitedTypes[node] then
        return indent(offset) .. string.format(
            "<recursive %s>\n", tostring(node.kind))
    end
    visitedTypes[node] = true
    local result = M.stringTree(node, offset)
    visitedTypes[node] = nil
    return result
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

---Append a list of TypedType children using the cycle-guarded printer.
---@param buf string[]
---@param children TypedType[]|nil
---@param offset integer
local function appendTypeChildren(buf, children, offset)
    if children == nil then
        return
    end
    for _, c in ipairs(children) do
        if c ~= nil then
            buf[#buf + 1] = formatType(c, offset)
        end
    end
end

---@param buf string[]
---@param node any node with a `type_` field
---@param offset integer
local function appendType(buf, node, offset)
    if node.type_ == nil then
        return
    end
    buf[#buf + 1] = indent(offset) .. "Type\n"
    buf[#buf + 1] = formatType(node.type_, offset + 1)
end

---@param buf string[]
---@param node any node with a `declaredType` field
---@param offset integer
local function appendDeclaredType(buf, node, offset)
    if node.declaredType == nil then
        return
    end
    buf[#buf + 1] = indent(offset) .. "DeclaredType\n"
    buf[#buf + 1] = formatType(node.declaredType, offset + 1)
end

local handlers = {}

-- module --------------------------------------------------------------------

---Format a typed module. Dependencies are sorted by module name for stable
---diffs. Definitions are emitted in their stored order.
---@param module TypedModule
---@param offset integer
---@return string
function M.moduleStringTree(module, offset)
    local buf = {
        indent(offset) .. string.format("TyModule(name=%s)\n", formatName(module.name)),
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
            "TyDependency(module=%s, names=%s)\n",
            formatName(k), formatStringList(sorted))
    end
    appendChildren(buf, module.definitions, offset + 1)
    return table.concat(buf)
end

---@param node TypedDefinition
---@param offset integer
handlers.TypedDefinition = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyDefinition(name=%s, hidden=%s)\n",
            formatName(node.name), formatBool(node.hidden)),
    }
    appendChildren(buf, node.params, offset + 1)
    if node.body ~= nil then
        buf[#buf + 1] = format(node.body, offset + 1)
    end
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

-- expressions ---------------------------------------------------------------

---@param node TyAccess
---@param offset integer
handlers.TyAccess = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyAccess(fieldName=%s)\n", formatName(node.fieldName)),
    }
    if node.record ~= nil then
        buf[#buf + 1] = format(node.record, offset + 1)
    end
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyApply
---@param offset integer
handlers.TyApply = function(node, offset)
    local buf = { indent(offset) .. "TyApply()\n" }
    if node.func ~= nil then
        buf[#buf + 1] = format(node.func, offset + 1)
    end
    appendChildren(buf, node.args, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyCall
---@param offset integer
handlers.TyCall = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyCall(name=%s)\n", formatName(node.name)),
    }
    appendChildren(buf, node.args, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyConst
---@param offset integer
handlers.TyConst = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyConst(value=%s)\n", formatConst(node.value)),
    }
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyConstructor
---@param offset integer
handlers.TyConstructor = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyConstructor(dataName=%s, optionName=%s)\n",
            formatName(node.dataName), formatName(node.optionName)),
    }
    appendChildren(buf, node.args, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyGlobal
---@param offset integer
handlers.TyGlobal = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyGlobal(moduleName=%s, definitionName=%s)\n",
            formatName(node.moduleName), formatName(node.definitionName)),
    }
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyLet
---@param offset integer
handlers.TyLet = function(node, offset)
    local buf = { indent(offset) .. "TyLet()\n" }
    if node.pattern ~= nil then
        buf[#buf + 1] = format(node.pattern, offset + 1)
    end
    if node.value ~= nil then
        buf[#buf + 1] = format(node.value, offset + 1)
    end
    if node.body ~= nil then
        buf[#buf + 1] = format(node.body, offset + 1)
    end
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyList
---@param offset integer
handlers.TyList = function(node, offset)
    local buf = { indent(offset) .. "TyList()\n" }
    appendChildren(buf, node.items, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyLocal
---@param offset integer
handlers.TyLocal = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyLocal(name=%s)\n", formatName(node.name)),
    }
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyRecord
---@param offset integer
handlers.TyRecord = function(node, offset)
    local buf = { indent(offset) .. "TyRecord()\n" }
    for _, fld in ipairs(node.fields) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "TyRecordField(name=%s)\n", formatName(fld.name))
        if fld.value ~= nil then
            buf[#buf + 1] = format(fld.value, offset + 2)
        end
    end
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TySelect
---@param offset integer
handlers.TySelect = function(node, offset)
    local buf = { indent(offset) .. "TySelect()\n" }
    if node.condition ~= nil then
        buf[#buf + 1] = format(node.condition, offset + 1)
    end
    for _, c in ipairs(node.cases) do
        buf[#buf + 1] = indent(offset + 1) .. "TySelectCase()\n"
        if c.pattern ~= nil then
            buf[#buf + 1] = format(c.pattern, offset + 2)
        end
        if c.expression ~= nil then
            buf[#buf + 1] = format(c.expression, offset + 2)
        end
    end
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyTuple
---@param offset integer
handlers.TyTuple = function(node, offset)
    local buf = { indent(offset) .. "TyTuple()\n" }
    appendChildren(buf, node.items, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyUpdate
---@param offset integer
handlers.TyUpdate = function(node, offset)
    local moduleStr
    if node.moduleName ~= nil and node.moduleName ~= "" then
        moduleStr = formatName(node.moduleName)
    else
        moduleStr = "<nil>"
    end
    local buf = {
        indent(offset) .. string.format(
            "TyUpdate(moduleName=%s, recordName=%s)\n",
            moduleStr, formatName(node.recordName)),
    }
    for _, fld in ipairs(node.fields) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "TyRecordField(name=%s)\n", formatName(fld.name))
        if fld.value ~= nil then
            buf[#buf + 1] = format(fld.value, offset + 2)
        end
    end
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

-- patterns ------------------------------------------------------------------

---@param node TyPAlias
---@param offset integer
handlers.TyPAlias = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyPAlias(alias=%s)\n", formatName(node.alias)),
    }
    if node.nested ~= nil then
        buf[#buf + 1] = format(node.nested, offset + 1)
    end
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyPAny
---@param offset integer
handlers.TyPAny = function(node, offset)
    local buf = { indent(offset) .. "TyPAny()\n" }
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyPCons
---@param offset integer
handlers.TyPCons = function(node, offset)
    local buf = { indent(offset) .. "TyPCons()\n" }
    if node.head ~= nil then
        buf[#buf + 1] = format(node.head, offset + 1)
    end
    if node.tail ~= nil then
        buf[#buf + 1] = format(node.tail, offset + 1)
    end
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyPConst
---@param offset integer
handlers.TyPConst = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyPConst(value=%s)\n", formatConst(node.value)),
    }
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyPList
---@param offset integer
handlers.TyPList = function(node, offset)
    local buf = { indent(offset) .. "TyPList()\n" }
    appendChildren(buf, node.items, offset + 1)
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyPNamed
---@param offset integer
handlers.TyPNamed = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TyPNamed(name=%s)\n", formatName(node.name)),
    }
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyPOption
---@param offset integer
handlers.TyPOption = function(node, offset)
    local defName = "<nil>"
    if node.definition ~= nil then
        defName = formatName(node.definition.name)
    end
    local buf = {
        indent(offset) .. string.format(
            "TyPOption(definitionName=%s)\n", defName),
    }
    appendChildren(buf, node.args, offset + 1)
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyPRecord
---@param offset integer
handlers.TyPRecord = function(node, offset)
    local buf = { indent(offset) .. "TyPRecord()\n" }
    for _, field in ipairs(node.fields) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "TyPRecordField(name=%s)\n", formatName(field.name))
    end
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

---@param node TyPTuple
---@param offset integer
handlers.TyPTuple = function(node, offset)
    local buf = { indent(offset) .. "TyPTuple()\n" }
    appendChildren(buf, node.items, offset + 1)
    appendDeclaredType(buf, node, offset + 1)
    appendType(buf, node, offset + 1)
    return table.concat(buf)
end

-- types ---------------------------------------------------------------------

---@param node TData
---@param offset integer
handlers.TData = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TData(name=%s)\n", formatName(node.name)),
    }
    appendTypeChildren(buf, node.args, offset + 1)
    for _, opt in ipairs(node.options) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "DataOption(name=%s)\n", formatName(opt.name))
        appendTypeChildren(buf, opt.values, offset + 2)
    end
    return table.concat(buf)
end

---@param node TFunc
---@param offset integer
handlers.TFunc = function(node, offset)
    local buf = { indent(offset) .. "TFunc()\n" }
    appendTypeChildren(buf, node.params, offset + 1)
    if node.return_ ~= nil then
        buf[#buf + 1] = formatType(node.return_, offset + 1)
    end
    return table.concat(buf)
end

---@param node TNative
---@param offset integer
handlers.TNative = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TNative(name=%s)\n", formatName(node.name)),
    }
    appendTypeChildren(buf, node.args, offset + 1)
    return table.concat(buf)
end

---@param node TRecord
---@param offset integer
handlers.TRecord = function(node, offset)
    local buf = {
        indent(offset) .. string.format(
            "TRecord(mayHaveMoreFields=%s)\n", formatBool(node.mayHaveMoreFields)),
    }
    ---@type Identifier[]
    local keys = {}
    for k in pairs(node.fields) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    for _, k in ipairs(keys) do
        buf[#buf + 1] = indent(offset + 1) .. string.format(
            "TRecordField(name=%s)\n", formatName(k))
        local ft = node.fields[k]
        if ft ~= nil then
            buf[#buf + 1] = formatType(ft, offset + 2)
        end
    end
    return table.concat(buf)
end

---@param node TTuple
---@param offset integer
handlers.TTuple = function(node, offset)
    local buf = { indent(offset) .. "TTuple()\n" }
    appendTypeChildren(buf, node.items, offset + 1)
    return table.concat(buf)
end

---@param node TUnbound
---@param offset integer
handlers.TUnbound = function(node, offset)
    return indent(offset) .. string.format(
        "TUnbound(index=%d, constraint=%s, name=%s)\n",
        node.index, formatName(node.constraint), formatName(node.givenName))
end

---Format any typed AST node as a tree.
---@param node any
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
