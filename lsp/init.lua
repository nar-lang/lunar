---Lunar Language Server (LSP).
---
---Implements a small but useful subset of the Language Server Protocol
---against the existing parser/compiler:
---
---  initialize / shutdown / exit
---  textDocument/didOpen / didChange / didClose / didSave
---  textDocument/publishDiagnostics   (parse + compile errors)
---  textDocument/hover                (signature + doc comment)
---  textDocument/definition           (jump to symbol)
---  textDocument/references           (workspace-wide identifier search)
---  textDocument/documentSymbol       (outline view)
---  textDocument/completion           (top-level identifiers)
---  textDocument/semanticTokens/full  (basic colouring boost)
---
---The server treats every `.nar` file under the workspace folder as
---part of one logical project. On `initialize` we recursively walk the
---workspace, parse every `.nar` file we find, and build a symbol
---table. Document edits invalidate just the changed file.

local Transport = require("lunar.lsp.transport")
local Json      = require("lunar.lsp.json")
local Compiler  = require("lunar.compiler")
local Docs      = require("lunar.compiler.docs")

local Lsp = {}

-- ----------------------------------------------------------------------------
-- LSP constants
-- ----------------------------------------------------------------------------

-- Diagnostic severities (per LSP spec).
local DIAG_ERROR   = 1
local DIAG_WARNING = 2

-- SymbolKind values relevant to Nar.
local SYMBOL_FUNCTION = 12
local SYMBOL_CLASS    = 5    -- used for data types
local SYMBOL_INTERFACE = 11  -- used for aliases
local SYMBOL_OPERATOR = 25
local SYMBOL_CONSTANT = 14

-- Completion item kinds.
local COMP_FUNCTION = 3
local COMP_CONSTRUCTOR = 4
local COMP_VARIABLE = 6
local COMP_CLASS = 7
local COMP_INTERFACE = 8
local COMP_OPERATOR = 24

-- Semantic-token legend (matches lunar.compiler.ast.tokens.TokenTypeLegend).
local TOKEN_TYPES = {
    "namespace", "type", "class", "enum", "interface", "struct",
    "typeParameter", "parameter", "variable", "property", "enumMember",
    "event", "function", "method", "macro", "keyword", "modifier",
    "comment", "string", "number", "regexp", "operator", "decorator",
}
local TOKEN_MODS = {
    "declaration", "definition", "readonly", "static", "deprecated",
    "abstract", "async", "modification", "documentation", "defaultLibrary",
}

-- ----------------------------------------------------------------------------
-- URI <-> file path helpers
-- ----------------------------------------------------------------------------

---Decode a percent-encoded URI path.
---@param s string
---@return string
local function urlDecode(s)
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

---Convert a `file://` URI to a local filesystem path.
---@param uri string
---@return string
local function uriToPath(uri)
    if uri:sub(1, 7) == "file://" then
        local rest = uri:sub(8)
        -- Drop the (optional) host segment.
        local _, slash = rest:find("^[^/]*/")
        if slash then rest = rest:sub(slash) end
        return urlDecode(rest)
    end
    return urlDecode(uri)
end

---Convert a filesystem path to a `file://` URI. Spaces are escaped;
---other valid path characters are passed through verbatim.
---@param path string
---@return string
local function pathToUri(path)
    local escaped = path:gsub(" ", "%%20")
    if escaped:sub(1, 1) == "/" then
        return "file://" .. escaped
    end
    return "file:///" .. escaped
end

-- ----------------------------------------------------------------------------
-- Document store + workspace index
-- ----------------------------------------------------------------------------

-- Map of `path -> { text, version, parsedModule, parseErrors, fileContent }`.
-- `text` and `parsedModule.location.fileContent` are kept in sync.
local docs = {}

-- Map of `moduleName -> path` so we can resolve cross-file definitions.
local moduleIndex = {}

-- Recorded workspace roots (filesystem paths).
local workspaceRoots = {}

---Re-parse a single file's text and refresh its cache entry.
---@param path string
---@param text string
local function reparse(path, text)
    local entry = docs[path] or {}
    entry.text = text
    local m, errs = Compiler.parse(path, text)
    entry.parsedModule = m
    entry.parseErrors = errs or {}
    docs[path] = entry
    -- Refresh the module-name index.
    for name, p in pairs(moduleIndex) do
        if p == path then moduleIndex[name] = nil end
    end
    if m ~= nil then
        moduleIndex[m.name] = path
    end
end

---Walk `dir` recursively, returning every `.nar` file found.
---Uses POSIX `find`; works on macOS/Linux. Silent on errors.
---@param dir string
---@return string[]
local function scanNarFiles(dir)
    local out = {}
    local cmd = string.format(
        "find %q -type f -name '*.nar' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null",
        dir)
    local p = io.popen(cmd, "r")
    if p == nil then return out end
    for line in p:lines() do
        out[#out + 1] = line
    end
    p:close()
    return out
end

---Read an entire file as text, or `nil` if it can't be opened.
---@param path string
---@return string|nil
local function readFile(path)
    local f = io.open(path, "rb")
    if f == nil then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

---Parse every `.nar` file under `root` into the document store.
---@param root string
local function indexWorkspace(root)
    workspaceRoots[#workspaceRoots + 1] = root
    for _, path in ipairs(scanNarFiles(root)) do
        if docs[path] == nil then
            local content = readFile(path)
            if content ~= nil then
                reparse(path, content)
            end
        end
    end
end

-- ----------------------------------------------------------------------------
-- Position / range helpers
-- ----------------------------------------------------------------------------

---Build an LSP Range from a `Location`. LSP positions are 0-based.
---@param loc Location|nil
---@return table|nil
local function locToRange(loc)
    if loc == nil or loc.isEmpty == nil then return nil end
    if loc:isEmpty() then return nil end
    return {
        start   = { line = (loc.startLine or 1) - 1, character = (loc.startColumn or 1) - 1 },
        ["end"] = { line = (loc.endLine   or 1) - 1, character = (loc.endColumn   or 1) - 1 },
    }
end

---Convert an LSP position (0-based line + character) to a 1-based
---byte offset within `text`. Returns 1 if the position falls before
---the buffer, `#text + 1` if it falls past the end.
---@param text string
---@param line integer
---@param ch integer
---@return integer
local function positionToOffset(text, line, ch)
    local offset = 1
    local curLine = 0
    while curLine < line do
        local nl = text:find("\n", offset, true)
        if nl == nil then return #text + 1 end
        offset = nl + 1
        curLine = curLine + 1
    end
    return offset + ch
end

---Identify the identifier (or operator) covering `offset`. Returns
---name + the 1-based start/end byte offsets, or nil if none.
---@param text string
---@param offset integer
---@return string|nil name
---@return integer|nil startOff
---@return integer|nil endOff
local function wordAtOffset(text, offset)
    if offset < 1 then offset = 1 end
    if offset > #text + 1 then offset = #text + 1 end

    local function isIdent(c)
        return c ~= "" and c:match("[%w_%.]") ~= nil
    end
    local function isOp(c)
        return c ~= "" and c:match("[%+%-%*/%%%^&|<>=!~%?]") ~= nil
    end

    local cur = text:sub(offset, offset)
    local prev = text:sub(offset - 1, offset - 1)

    -- Identifier (letters/digits/underscore/dot for qualified names).
    if isIdent(cur) or isIdent(prev) then
        local s = offset
        while s > 1 and isIdent(text:sub(s - 1, s - 1)) do s = s - 1 end
        local e = offset
        while e <= #text and isIdent(text:sub(e, e)) do e = e + 1 end
        if e > s then
            return text:sub(s, e - 1), s, e
        end
    end

    -- Operator (sequence of symbol characters).
    if isOp(cur) or isOp(prev) then
        local s = offset
        while s > 1 and isOp(text:sub(s - 1, s - 1)) do s = s - 1 end
        local e = offset
        while e <= #text and isOp(text:sub(e, e)) do e = e + 1 end
        if e > s then
            return text:sub(s, e - 1), s, e
        end
    end

    return nil, nil, nil
end

---Convert a 1-based byte offset back to a 0-based LSP Position.
---@param text string
---@param offset integer
---@return table
local function offsetToPosition(text, offset)
    if offset < 1 then offset = 1 end
    local line = 0
    local lineStart = 1
    local i = 1
    while i < offset do
        local nl = text:find("\n", i, true)
        if nl == nil or nl >= offset then break end
        line = line + 1
        lineStart = nl + 1
        i = nl + 1
    end
    return { line = line, character = offset - lineStart }
end

-- ----------------------------------------------------------------------------
-- Symbol catalogue (built from the parsed modules in the document store)
-- ----------------------------------------------------------------------------

---@class SymbolEntry
---@field name string         -- bare identifier
---@field moduleName string
---@field path string
---@field kind string         -- "def" | "alias" | "type" | "infix" | "constructor"
---@field hidden boolean
---@field signature string|nil
---@field doc string|nil
---@field location Location

---@return SymbolEntry[]
local function allSymbols()
    local out = {}
    for path, entry in pairs(docs) do
        local m = entry.parsedModule
        if m ~= nil then
            for _, d in ipairs(m.definitions or {}) do
                out[#out + 1] = {
                    name = d.name, moduleName = m.name, path = path,
                    kind = "def", hidden = d.hidden == true,
                    signature = nil, doc = d.docComment and d.docComment.text or nil,
                    location = d.nameLocation,
                    fullLocation = d.location,
                    raw = d,
                }
            end
            for _, a in ipairs(m.aliases or {}) do
                out[#out + 1] = {
                    name = a.name, moduleName = m.name, path = path,
                    kind = "alias", hidden = a.hidden == true,
                    doc = a.docComment and a.docComment.text or nil,
                    location = a.nameLocation,
                    fullLocation = a.location,
                    raw = a,
                }
            end
            for _, t in ipairs(m.dataTypes or {}) do
                out[#out + 1] = {
                    name = t.name, moduleName = m.name, path = path,
                    kind = "type", hidden = t.hidden == true,
                    doc = t.docComment and t.docComment.text or nil,
                    location = t.nameLocation,
                    fullLocation = t.location,
                    raw = t,
                }
                for _, opt in ipairs(t.options or {}) do
                    if not opt.hidden then
                        out[#out + 1] = {
                            name = opt.name, moduleName = m.name, path = path,
                            kind = "constructor", hidden = false,
                            doc = nil,
                            location = opt.nameLocation,
                            fullLocation = opt.location,
                            raw = opt,
                            parentType = t.name,
                        }
                    end
                end
            end
            for _, op in ipairs(m.infixFns or {}) do
                out[#out + 1] = {
                    name = op.name, moduleName = m.name, path = path,
                    kind = "infix", hidden = op.hidden == true,
                    doc = op.docComment and op.docComment.text or nil,
                    location = op.aliasLocation,
                    fullLocation = op.location,
                    raw = op,
                }
            end
        end
    end
    return out
end

---Resolve a (possibly qualified) name to its symbol entry(s). When
---`preferModule` is given, matches inside that module are returned
---first so the surrounding-file's `map` wins over `Array.map` etc.
---@param name string
---@param preferModule string|nil
---@return SymbolEntry[]
local function lookupSymbol(name, preferModule)
    local module, bare = name:match("^(.+)%.([^%.]+)$")
    local results = {}
    for _, sym in ipairs(allSymbols()) do
        if module ~= nil then
            if sym.moduleName == module and sym.name == bare then
                results[#results + 1] = sym
            end
        else
            if sym.name == name then
                results[#results + 1] = sym
            end
        end
    end
    if preferModule ~= nil and #results > 1 then
        table.sort(results, function(a, b)
            local ap = (a.moduleName == preferModule) and 0 or 1
            local bp = (b.moduleName == preferModule) and 0 or 1
            if ap ~= bp then return ap < bp end
            return a.moduleName < b.moduleName
        end)
    end
    return results
end

-- ----------------------------------------------------------------------------
-- Signature rendering (re-used from the markdown docs generator)
-- ----------------------------------------------------------------------------

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function flatten(s)
    return trim((s:gsub("%s+", " ")))
end

local function defSignature(d)
    local content = d.location and d.location.fileContent or ""
    local prefix = content:sub(d.location.start, d.nameLocation.start - 1)
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
    local text = content:sub(s, e - 1)
    text = text:gsub("//.*$", ""):gsub("[%s]*=[%s]*$", "")
    text = flatten(text)
    if isNative then text = "native " .. text end
    return "def " .. text
end

local function aliasSignature(a)
    local header = a.name
    if a.params and #a.params > 0 then
        header = header .. "[" .. table.concat(a.params, ", ") .. "]"
    end
    if a.type == nil then
        return "alias native " .. header
    end
    local typeText = a.type.location.fileContent:sub(a.type.location.start, a.type.location.finish - 1)
    typeText = typeText:gsub("//.*$", "")
    return "alias " .. header .. " = " .. flatten(typeText)
end

local function dataTypeSignature(t)
    local content = t.location and t.location.fileContent or ""
    local header = t.name
    if t.params and #t.params > 0 then
        header = header .. "[" .. table.concat(t.params, ", ") .. "]"
    end
    local visible = {}
    for _, opt in ipairs(t.options or {}) do
        if not opt.hidden then
            local raw = content:sub(opt.location.start, opt.location.finish - 1)
            raw = raw:gsub("//.*$", "")
            visible[#visible + 1] = flatten(raw)
        end
    end
    if #visible == 0 then return "type " .. header end
    local lines = { "type " .. header }
    for i, v in ipairs(visible) do
        local pfx = (i == 1) and "  = " or "  | "
        lines[#lines + 1] = pfx .. v
    end
    return table.concat(lines, "\n")
end

local function infixSignature(op)
    local assoc = "non"
    if op.associativity == 1 then assoc = "left"
    elseif op.associativity == 2 then assoc = "right" end
    return string.format("infix (%s): (%s %d) = %s",
        op.name, assoc, op.precedence, op.alias)
end

local function symbolSignature(sym)
    if sym.kind == "def"   then return defSignature(sym.raw)       end
    if sym.kind == "alias" then return aliasSignature(sym.raw)     end
    if sym.kind == "type"  then return dataTypeSignature(sym.raw)  end
    if sym.kind == "infix" then return infixSignature(sym.raw)     end
    if sym.kind == "constructor" then
        local optName = sym.raw.name
        if #(sym.raw.values or {}) == 0 then
            return optName
        end
        local parts = {}
        for _, v in ipairs(sym.raw.values) do
            local txt = v.type.location.fileContent:sub(v.type.location.start, v.type.location.finish - 1)
            parts[#parts + 1] = flatten(txt)
        end
        return optName .. "(" .. table.concat(parts, ", ") .. ")"
    end
    return sym.name
end

-- ----------------------------------------------------------------------------
-- Diagnostics
-- ----------------------------------------------------------------------------

---Convert a `"msg at file:offset"` compiler error to an LSP diagnostic.
---@param err string
---@param text string
---@return table
local function diagnosticFromError(err, text)
    local message, offset = err:match("^(.+) at .-:(%d+)$")
    local pos
    if offset ~= nil then
        pos = offsetToPosition(text, tonumber(offset))
    else
        pos = { line = 0, character = 0 }
        message = err
    end
    local endPos = { line = pos.line, character = pos.character + 1 }
    return {
        range    = { start = pos, ["end"] = endPos },
        severity = DIAG_ERROR,
        source   = "lunar",
        message  = message,
    }
end

---Publish diagnostics for a single document URI.
---@param uri string
---@param path string
local function publishDiagnostics(uri, path)
    local entry = docs[path]
    if entry == nil then return end
    local diags = {}
    for _, err in ipairs(entry.parseErrors or {}) do
        diags[#diags + 1] = diagnosticFromError(err, entry.text)
    end
    Transport.write({
        jsonrpc = "2.0",
        method  = "textDocument/publishDiagnostics",
        params  = {
            uri         = uri,
            diagnostics = (#diags == 0) and Json.EMPTY_ARRAY or diags,
        },
    })
end

-- ----------------------------------------------------------------------------
-- Hover
-- ----------------------------------------------------------------------------

local function makeHover(sym)
    local lines = {
        "```nar",
        symbolSignature(sym),
        "```",
    }
    if sym.doc and sym.doc ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = sym.doc
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "_from `" .. sym.moduleName .. "`_"
    return {
        contents = {
            kind  = "markdown",
            value = table.concat(lines, "\n"),
        },
    }
end

-- ----------------------------------------------------------------------------
-- Request handlers
-- ----------------------------------------------------------------------------

local handlers = {}

function handlers.initialize(params)
    local roots = {}
    if params.workspaceFolders ~= nil then
        for _, wf in ipairs(params.workspaceFolders) do
            roots[#roots + 1] = uriToPath(wf.uri)
        end
    end
    if #roots == 0 and params.rootUri ~= nil and params.rootUri ~= Json.NULL then
        roots[#roots + 1] = uriToPath(params.rootUri)
    end
    if #roots == 0 and params.rootPath ~= nil and params.rootPath ~= Json.NULL then
        roots[#roots + 1] = params.rootPath
    end
    for _, r in ipairs(roots) do indexWorkspace(r) end

    return {
        capabilities = {
            textDocumentSync = {
                openClose = true,
                change    = 1,  -- 1 = Full
                save      = { includeText = false },
            },
            hoverProvider          = true,
            definitionProvider     = true,
            referencesProvider     = true,
            documentSymbolProvider = true,
            completionProvider     = {
                triggerCharacters = { ".", " " },
                resolveProvider   = false,
            },
            semanticTokensProvider = {
                legend = {
                    tokenTypes     = TOKEN_TYPES,
                    tokenModifiers = TOKEN_MODS,
                },
                range = false,
                full  = true,
            },
        },
        serverInfo = {
            name    = "lunar-lsp",
            version = "0.1.0",
        },
    }
end

function handlers.initialized()
    -- Publish diagnostics for everything we discovered up-front so the
    -- client can show "problems" before the user opens a file.
    for path in pairs(docs) do
        publishDiagnostics(pathToUri(path), path)
    end
end

function handlers.shutdown() return Json.NULL end
function handlers.exit() os.exit(0) end

-- ---- Document synchronization --------------------------------------

handlers["textDocument/didOpen"] = function(params)
    local doc = params.textDocument
    local path = uriToPath(doc.uri)
    reparse(path, doc.text or "")
    if docs[path] then docs[path].version = doc.version end
    publishDiagnostics(doc.uri, path)
end

handlers["textDocument/didChange"] = function(params)
    local path = uriToPath(params.textDocument.uri)
    local changes = params.contentChanges
    if #changes == 0 then return end
    -- Full-sync mode: the last change always carries the complete new text.
    local last = changes[#changes]
    reparse(path, last.text or "")
    if docs[path] then docs[path].version = params.textDocument.version end
    publishDiagnostics(params.textDocument.uri, path)
end

handlers["textDocument/didSave"] = function(params)
    local path = uriToPath(params.textDocument.uri)
    -- If the client doesn't send text, re-read from disk to keep in sync.
    if params.text == nil then
        local content = readFile(path)
        if content ~= nil then reparse(path, content) end
    else
        reparse(path, params.text)
    end
    publishDiagnostics(params.textDocument.uri, path)
end

handlers["textDocument/didClose"] = function(params)
    -- Don't drop from the index: the file is still useful for cross-file
    -- navigation. Just re-read from disk to discard any unsaved edits.
    local path = uriToPath(params.textDocument.uri)
    local content = readFile(path)
    if content ~= nil then
        reparse(path, content)
        publishDiagnostics(params.textDocument.uri, path)
    end
end

-- ---- Hover ---------------------------------------------------------

handlers["textDocument/hover"] = function(params)
    local path = uriToPath(params.textDocument.uri)
    local entry = docs[path]
    if entry == nil then return Json.NULL end
    local offset = positionToOffset(entry.text,
        params.position.line, params.position.character)
    local word = wordAtOffset(entry.text, offset)
    if word == nil then return Json.NULL end
    local prefer = entry.parsedModule and entry.parsedModule.name or nil
    local matches = lookupSymbol(word, prefer)
    if #matches == 0 then return Json.NULL end
    return makeHover(matches[1])
end

-- ---- Definition ----------------------------------------------------

handlers["textDocument/definition"] = function(params)
    local path = uriToPath(params.textDocument.uri)
    local entry = docs[path]
    if entry == nil then return Json.NULL end
    local offset = positionToOffset(entry.text,
        params.position.line, params.position.character)
    local word = wordAtOffset(entry.text, offset)
    if word == nil then return Json.EMPTY_ARRAY end
    local prefer = entry.parsedModule and entry.parsedModule.name or nil
    local matches = lookupSymbol(word, prefer)
    local locs = {}
    for _, sym in ipairs(matches) do
        local r = locToRange(sym.fullLocation or sym.location)
        if r ~= nil then
            locs[#locs + 1] = { uri = pathToUri(sym.path), range = r }
        end
    end
    if #locs == 0 then return Json.EMPTY_ARRAY end
    return locs
end

-- ---- References ----------------------------------------------------

---Iterate over every occurrence of the identifier `name` in `text`,
---returning their 1-based byte offsets.
---@param text string
---@param name string
---@return integer[]
local function findIdentOccurrences(text, name)
    local out = {}
    local nameLen = #name
    if nameLen == 0 then return out end
    local i = 1
    while true do
        local s = text:find(name, i, true)
        if s == nil then break end
        local e = s + nameLen - 1
        local before = (s > 1) and text:sub(s - 1, s - 1) or ""
        local after = text:sub(e + 1, e + 1)
        local isIdent = function(c) return c ~= "" and c:match("[%w_]") ~= nil end
        if not isIdent(before) and not isIdent(after) then
            out[#out + 1] = s
        end
        i = e + 1
    end
    return out
end

handlers["textDocument/references"] = function(params)
    local path = uriToPath(params.textDocument.uri)
    local entry = docs[path]
    if entry == nil then return Json.EMPTY_ARRAY end
    local offset = positionToOffset(entry.text,
        params.position.line, params.position.character)
    local word = wordAtOffset(entry.text, offset)
    if word == nil then return Json.EMPTY_ARRAY end
    -- Use the bare name (drop module qualifier) for the text search.
    local bare = word:match("([^%.]+)$") or word

    local locs = {}
    for p, e in pairs(docs) do
        for _, off in ipairs(findIdentOccurrences(e.text, bare)) do
            local startPos = offsetToPosition(e.text, off)
            local endPos = offsetToPosition(e.text, off + #bare)
            locs[#locs + 1] = {
                uri   = pathToUri(p),
                range = { start = startPos, ["end"] = endPos },
            }
        end
    end
    if #locs == 0 then return Json.EMPTY_ARRAY end
    return locs
end

-- ---- Document symbols ----------------------------------------------

handlers["textDocument/documentSymbol"] = function(params)
    local path = uriToPath(params.textDocument.uri)
    local entry = docs[path]
    if entry == nil or entry.parsedModule == nil then return Json.EMPTY_ARRAY end
    local m = entry.parsedModule
    local out = {}

    local function add(name, kind, loc, detail, children)
        local range = locToRange(loc)
        if range == nil then return end
        out[#out + 1] = {
            name           = name,
            detail         = detail,
            kind           = kind,
            range          = range,
            selectionRange = range,
            children       = children or Json.EMPTY_ARRAY,
        }
    end

    for _, t in ipairs(m.dataTypes or {}) do
        if not t.hidden then
            local children = {}
            for _, opt in ipairs(t.options or {}) do
                if not opt.hidden then
                    local r = locToRange(opt.location)
                    if r ~= nil then
                        children[#children + 1] = {
                            name           = opt.name,
                            kind           = SYMBOL_CONSTANT,
                            range          = r,
                            selectionRange = r,
                            children       = Json.EMPTY_ARRAY,
                        }
                    end
                end
            end
            add(t.name, SYMBOL_CLASS, t.location, "type",
                (#children == 0) and Json.EMPTY_ARRAY or children)
        end
    end
    for _, a in ipairs(m.aliases or {}) do
        if not a.hidden then add(a.name, SYMBOL_INTERFACE, a.location, "alias") end
    end
    for _, d in ipairs(m.definitions or {}) do
        if not d.hidden then add(d.name, SYMBOL_FUNCTION, d.location, "def") end
    end
    for _, op in ipairs(m.infixFns or {}) do
        if not op.hidden then add(op.name, SYMBOL_OPERATOR, op.location, "infix") end
    end

    if #out == 0 then return Json.EMPTY_ARRAY end
    return out
end

-- ---- Completion ----------------------------------------------------

local function completionKind(kind)
    if kind == "def" then return COMP_FUNCTION end
    if kind == "constructor" then return COMP_CONSTRUCTOR end
    if kind == "type" then return COMP_CLASS end
    if kind == "alias" then return COMP_INTERFACE end
    if kind == "infix" then return COMP_OPERATOR end
    return COMP_VARIABLE
end

handlers["textDocument/completion"] = function(params)
    local seen = {}
    local items = {}
    for _, sym in ipairs(allSymbols()) do
        if not sym.hidden then
            local key = sym.kind .. "\0" .. sym.name
            if not seen[key] then
                seen[key] = true
                items[#items + 1] = {
                    label  = sym.name,
                    kind   = completionKind(sym.kind),
                    detail = sym.moduleName,
                    documentation = (sym.doc ~= nil) and {
                        kind  = "markdown",
                        value = "```nar\n" .. symbolSignature(sym) .. "\n```\n\n" .. sym.doc,
                    } or nil,
                }
            end
        end
    end
    if #items == 0 then return Json.EMPTY_ARRAY end
    return { isIncomplete = false, items = items }
end

-- ---- Semantic tokens (very basic — declarations only) --------------

---Encode a list of {line, char, length, type, mods} tuples as the
---delta-compressed integer array LSP expects.
local function encodeTokens(tokens)
    table.sort(tokens, function(a, b)
        if a.line ~= b.line then return a.line < b.line end
        return a.char < b.char
    end)
    local data = {}
    local prevLine, prevChar = 0, 0
    for _, tok in ipairs(tokens) do
        local dLine = tok.line - prevLine
        local dChar = (dLine == 0) and (tok.char - prevChar) or tok.char
        data[#data + 1] = dLine
        data[#data + 1] = dChar
        data[#data + 1] = tok.length
        data[#data + 1] = tok.type
        data[#data + 1] = tok.mods or 0
        prevLine, prevChar = tok.line, tok.char
    end
    return data
end

local SEM_TYPE         = 1
local SEM_CLASS        = 2
local SEM_FUNCTION     = 12
local SEM_OPERATOR     = 21
local MOD_DECLARATION  = 0x001
local MOD_DEFAULT_LIB  = 0x200

local function addTokenFromLocation(out, loc, type_, mods)
    if loc == nil or loc.startLine == nil then return end
    if loc.endLine ~= loc.startLine then return end -- LSP requires single-line
    out[#out + 1] = {
        line   = loc.startLine - 1,
        char   = loc.startColumn - 1,
        length = (loc.endColumn or loc.startColumn) - loc.startColumn,
        type   = type_,
        mods   = mods or 0,
    }
end

handlers["textDocument/semanticTokens/full"] = function(params)
    local path = uriToPath(params.textDocument.uri)
    local entry = docs[path]
    if entry == nil or entry.parsedModule == nil then
        return { data = Json.EMPTY_ARRAY }
    end
    local m = entry.parsedModule
    local toks = {}
    for _, d in ipairs(m.definitions or {}) do
        addTokenFromLocation(toks, d.nameLocation, SEM_FUNCTION, MOD_DECLARATION)
    end
    for _, a in ipairs(m.aliases or {}) do
        addTokenFromLocation(toks, a.nameLocation, SEM_TYPE, MOD_DECLARATION)
    end
    for _, t in ipairs(m.dataTypes or {}) do
        addTokenFromLocation(toks, t.nameLocation, SEM_CLASS, MOD_DECLARATION)
        for _, opt in ipairs(t.options or {}) do
            addTokenFromLocation(toks, opt.nameLocation, SEM_CLASS, MOD_DECLARATION)
        end
    end
    for _, op in ipairs(m.infixFns or {}) do
        addTokenFromLocation(toks, op.aliasLocation, SEM_OPERATOR, MOD_DECLARATION)
    end
    return { data = encodeTokens(toks) }
end

-- ----------------------------------------------------------------------------
-- Main loop
-- ----------------------------------------------------------------------------

local function dispatch(msg)
    local method = msg.method
    if method == nil then return end
    local handler = handlers[method]
    if handler == nil then
        if msg.id ~= nil then
            -- Method not found.
            Transport.write({
                jsonrpc = "2.0",
                id      = msg.id,
                error   = { code = -32601, message = "method not found: " .. method },
            })
        end
        return
    end
    local ok, resultOrErr = pcall(handler, msg.params or {})
    if msg.id == nil then
        -- Notification — never reply, but surface handler crashes to stderr.
        if not ok then
            io.stderr:write("lsp: handler `" .. method .. "` crashed: " .. tostring(resultOrErr) .. "\n")
        end
        return
    end
    if not ok then
        Transport.write({
            jsonrpc = "2.0",
            id      = msg.id,
            error   = { code = -32603, message = tostring(resultOrErr) },
        })
        return
    end
    Transport.write({
        jsonrpc = "2.0",
        id      = msg.id,
        result  = resultOrErr,
    })
end

---Run the LSP server loop until stdin closes.
function Lsp.run()
    Transport.setup()
    while true do
        local msg = Transport.read()
        if msg == nil then break end
        dispatch(msg)
    end
end

return Lsp
