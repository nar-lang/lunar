---Documentation generator for parsed Nar modules.
---
---`Docs.collect(parsedModules)` walks the public top-level entities of
---each module (aliases, data types, definitions, and infix operators)
---and harvests the `docComment` field attached by the parser plus a
---rendered signature reconstructed from the source text.
---
---`Docs.render(docs, packageName)` produces a single Markdown document
---with a table-of-contents and one section per module. Inside each
---module entries are grouped by kind (Types, Aliases, Definitions,
---Operators) and sorted alphabetically.
---
---Hidden entities (`alias hidden`, `def hidden`, `type hidden`,
---`infix hidden`, and hidden data-type options) are skipped entirely.

local Docs = {}

---@class DocEntry
---@field name string         -- bare identifier (e.g. "map", "Maybe", "|>")
---@field kind string         -- "type" | "alias" | "def" | "infix"
---@field comment string|nil  -- raw doc-comment text (Markdown), or nil
---@field hidden boolean
---@field signature string|nil

---@class ModuleDoc
---@field name string
---@field entries DocEntry[]

---@class Docs
---@field modules ModuleDoc[]

-- ----------------------------------------------------------------------------
-- Source-slicing helpers
-- ----------------------------------------------------------------------------

---@param loc Location|nil
---@return string
local function locText(loc)
    if loc == nil or loc.fileContent == nil then
        return ""
    end
    return loc.fileContent:sub(loc.start, loc.finish - 1)
end

---@param content string|nil
---@param start integer|nil
---@param finish integer|nil
---@return string
local function sliceSource(content, start, finish)
    if content == nil or content == "" or start == nil or finish == nil then
        return ""
    end
    if finish <= start then
        return ""
    end
    return content:sub(start, finish - 1)
end

---Collapse runs of whitespace into single spaces; trim ends.
---@param s string
---@return string
local function flatten(s)
    s = (s:gsub("%s+", " "))
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- ----------------------------------------------------------------------------
-- Signature rendering (text-based — we reuse the original source slices to
-- preserve exact spelling of type expressions instead of re-printing the AST)
-- ----------------------------------------------------------------------------

---Render the signature of a top-level `def`. Strips the leading `def`
---keyword and the trailing `= body`, keeping just `name(params) -> RetType`
---(or `name: Type` for value definitions). `def native` declarations
---get a leading `native ` so readers know there's no Nar body.
---@param d Definition
---@return string
local function defSignature(d)
    local content = d.location and d.location.fileContent or ""
    -- Detect `def native` by inspecting the source between the start of
    -- the definition and the name. The parser injects a synthetic body
    -- for natives, so `d.body` is not a reliable signal on its own.
    local prefix = sliceSource(content, d.location.start, d.nameLocation.start)
    local isNative = prefix:find("%f[%w]native%f[%W]") ~= nil

    local s = d.nameLocation.start
    local e
    if isNative then
        e = d.declaredType and d.declaredType.location.finish or d.location.finish
    elseif d.body ~= nil then
        e = d.body.location.start
    elseif d.declaredType ~= nil then
        e = d.declaredType.location.finish
    else
        e = d.location.finish
    end
    local text = sliceSource(content, s, e)
    -- Strip anything past the first `//` we see; some parsers extend
    -- the location past the declared type into the next entity's
    -- trailing whitespace and doc comments.
    text = text:gsub("//.*$", "")
    text = text:gsub("[%s]*=[%s]*$", "")
    text = flatten(text)
    if isNative then
        text = "native " .. text
    end
    return text
end

---Render the signature of an `alias`. For a regular alias this is
---`name[params] = TypeText`; for `alias native Foo` it is `native Foo`
---(with `[params]` if present).
---@param a Alias
---@return string
local function aliasSignature(a)
    local header = a.name
    if a.params ~= nil and #a.params > 0 then
        header = header .. "[" .. table.concat(a.params, ", ") .. "]"
    end
    if a.type == nil then
        return "native " .. header
    end
    local typeText = locText(a.type)
    typeText = typeText:gsub("//.*$", "")
    return header .. " = " .. flatten(typeText)
end

---Render the signature of a `type` declaration, including its public
---options on separate lines. Hidden options are filtered out.
---@param t DataType
---@return string
local function dataTypeSignature(t)
    local content = t.location and t.location.fileContent or ""
    local header = t.name
    if t.params ~= nil and #t.params > 0 then
        header = header .. "[" .. table.concat(t.params, ", ") .. "]"
    end

    local visible = {}
    for _, opt in ipairs(t.options or {}) do
        if not opt.hidden then
            local raw = sliceSource(content,
                opt.location.start, opt.location.finish)
            -- The parser sometimes extends an option's `finish` past its
            -- own boundary, sweeping in any trailing comments / blank
            -- lines before the next top-level declaration. Cut at the
            -- first `//` we see so doc-comments for the next entity
            -- don't bleed in.
            raw = raw:gsub("//.*$", "")
            visible[#visible + 1] = flatten(raw)
        end
    end

    if #visible == 0 then
        return header
    end

    local lines = { header }
    for i, opt in ipairs(visible) do
        local prefix = (i == 1) and "  = " or "  | "
        lines[#lines + 1] = prefix .. opt
    end
    return table.concat(lines, "\n")
end

---Render the signature of an infix operator: associativity, precedence,
---and the underlying function alias.
---@param op Infix
---@return string
local function infixSignature(op)
    local assocName = "non"
    if op.associativity == 1 then
        assocName = "left"
    elseif op.associativity == 2 then
        assocName = "right"
    end
    return string.format("(%s): (%s %d) = %s",
        op.name, assocName, op.precedence, op.alias)
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

---Collect doc-comment information from a set of parsed modules.
---@param parsedModules table<string, table>  map of moduleName -> ParsedModule
---@return Docs
function Docs.collect(parsedModules)
    local moduleNames = {}
    for n in pairs(parsedModules) do
        moduleNames[#moduleNames + 1] = n
    end
    table.sort(moduleNames)

    local modules = {}
    for _, moduleName in ipairs(moduleNames) do
        local m = parsedModules[moduleName]
        local entries = {}

        for _, t in ipairs(m.dataTypes or {}) do
            entries[#entries + 1] = {
                name = t.name,
                kind = "type",
                comment = t.docComment and t.docComment.text or nil,
                hidden = t.hidden == true,
                signature = dataTypeSignature(t),
            }
        end

        for _, a in ipairs(m.aliases or {}) do
            entries[#entries + 1] = {
                name = a.name,
                kind = "alias",
                comment = a.docComment and a.docComment.text or nil,
                hidden = a.hidden == true,
                signature = aliasSignature(a),
            }
        end

        for _, d in ipairs(m.definitions or {}) do
            entries[#entries + 1] = {
                name = d.name,
                kind = "def",
                comment = d.docComment and d.docComment.text or nil,
                hidden = d.hidden == true,
                signature = defSignature(d),
            }
        end

        for _, op in ipairs(m.infixFns or {}) do
            entries[#entries + 1] = {
                name = op.name,
                kind = "infix",
                comment = op.docComment and op.docComment.text or nil,
                hidden = op.hidden == true,
                signature = infixSignature(op),
            }
        end

        modules[#modules + 1] = {
            name = moduleName,
            entries = entries,
        }
    end

    return { modules = modules }
end

---@type table<string, { label: string, plural: string, order: integer, prefix: string }>
local KIND_META = {
    type   = { label = "Type",     plural = "Types",       order = 1, prefix = "type "  },
    alias  = { label = "Alias",    plural = "Aliases",     order = 2, prefix = "alias " },
    def    = { label = "Function", plural = "Definitions", order = 3, prefix = ""       },
    infix  = { label = "Operator", plural = "Operators",   order = 4, prefix = "infix " },
}

---Slugify a Markdown heading the way GitHub does:
---  1. lowercase
---  2. strip every character that isn't alphanumeric, space, hyphen, or underscore
---     (so `.` and other punctuation are dropped, NOT turned into `-`)
---  3. replace runs of whitespace with single `-`
---@param s string
---@return string
local function mdAnchor(s)
    local a = s:lower()
    -- Drop characters GitHub strips. Keep word chars (letters/digits/_),
    -- spaces, and hyphens.
    a = a:gsub("[^%w%s%-_]+", "")
    -- Spaces -> dashes.
    a = a:gsub("%s+", "-")
    a = a:gsub("^%-+", ""):gsub("%-+$", "")
    return a
end

---@param e DocEntry
---@return string
local function entrySortKey(e)
    return (e.name or ""):lower()
end

---Render a collected `Docs` value as a single Markdown string.
---@param docs Docs
---@param packageName string|nil  used in the document title; defaults to "Package"
---@return string
function Docs.render(docs, packageName)
    packageName = packageName or "Package"
    local out = {}

    local function w(s)
        out[#out + 1] = s
    end

    w("# " .. packageName .. " — API Documentation\n")
    w("")

    -- Index ----------------------------------------------------------
    w("## Modules\n")
    for _, m in ipairs(docs.modules) do
        local visible = false
        for _, e in ipairs(m.entries) do
            if not e.hidden then
                visible = true
                break
            end
        end
        if visible then
            w("- [" .. m.name .. "](#" .. mdAnchor(m.name) .. ")")
        end
    end
    w("")

    -- Per-module sections -------------------------------------------
    for _, m in ipairs(docs.modules) do
        local buckets = { type = {}, alias = {}, def = {}, infix = {} }
        local anyVisible = false
        for _, e in ipairs(m.entries) do
            if not e.hidden then
                buckets[e.kind][#buckets[e.kind] + 1] = e
                anyVisible = true
            end
        end
        if anyVisible then
            w("## " .. m.name .. "\n")

            local kinds = { "type", "alias", "def", "infix" }
            for _, kind in ipairs(kinds) do
                local bucket = buckets[kind]
                if #bucket > 0 then
                    table.sort(bucket, function(a, b)
                        return entrySortKey(a) < entrySortKey(b)
                    end)
                    w("### " .. KIND_META[kind].plural .. "\n")
                    for _, e in ipairs(bucket) do
                        w("#### `" .. e.name .. "`")
                        if e.signature and e.signature ~= "" then
                            w("")
                            w("```")
                            w(KIND_META[kind].prefix .. e.signature)
                            w("```")
                        end
                        if e.comment and e.comment ~= "" then
                            w("")
                            w(e.comment)
                        end
                        w("")
                    end
                end
            end
        end
    end

    return table.concat(out, "\n")
end

return Docs
