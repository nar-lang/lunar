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

-- Workspace-wide typed AST cache. These are lazily rebuilt on demand
-- whenever a navigation request needs semantic information. Any edit
-- invalidates the entire cache (cheap correctness; can optimize later).
local typedDirty       = true
local normalizedCache  = {} -- moduleName -> NormalizedModule
local typedCache       = {} -- moduleName -> TypedModule

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
    -- Any edit invalidates downstream semantic info.
    typedDirty      = true
    normalizedCache = {}
    typedCache      = {}
end

---Ensure the normalize + annotate stages have been run for every parsed
---module currently in the workspace. Errors are swallowed: partial typed
---modules are still useful for navigation. Safe to call repeatedly — the
---compiler skips already-populated entries.
local function ensureTyped()
    if not typedDirty then return end
    typedDirty = false
    local parsedModules = {}
    for _, entry in pairs(docs) do
        local m = entry.parsedModule
        if m ~= nil then
            parsedModules[m.name] = m
        end
    end
    -- The pipeline mutates `parsedModules` (calls `:generate`/`:normalize`
    -- which can install fields on the parsed nodes). That is harmless.
    pcall(Compiler.normalize, parsedModules, normalizedCache)
    pcall(Compiler.annotate, normalizedCache, typedCache)
    -- Validation runs the Hindley-Milner unifier so that hover can render
    -- solved types (e.g. `Char` instead of `u_1`). Failures here are
    -- non-fatal: partial typing is still navigable.
    pcall(Compiler.validate, typedCache)
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

---Find every `nar.json` under `dir` (any depth).
---@param dir string
---@return string[]
local function scanManifests(dir)
    local out = {}
    local cmd = string.format(
        "find %q -type f -name 'nar.json' -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/.build/*' 2>/dev/null",
        dir)
    local p = io.popen(cmd, "r")
    if p == nil then return out end
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end

---Lazy require to avoid a cycle when the LSP module is loaded outside a
---compile context.
local Packages = require("lunar.compiler.packages")

---Expand `~` in a path.
local function expandHome(p)
    if p == "~" then return os.getenv("HOME") or p end
    if p:sub(1, 2) == "~/" then
        local h = os.getenv("HOME"); if h == nil then return p end
        return h .. p:sub(2)
    end
    return p
end

---Locate a dependency package directory by name + repo URL. Searches
---workspace roots first (in case the user has the dep checked out as a
---sibling), then the lunar CLI cache (`~/.nar/<url>`). Returns the dir
---containing the matching `nar.json`, or nil.
---@param name string
---@param url string|nil
---@param searchDirs string[]
---@return string|nil
local function locatePackageDir(name, url, searchDirs)
    local function isFile(p) local f = io.open(p, "rb"); if f then f:close(); return true end; return false end
    local function manifestNameMatches(dir, expected)
        local m = readFile(dir .. "/nar.json"); if m == nil then return false end
        local parsed = Packages.parseJson(m)
        if type(parsed) ~= "table" then return false end
        return parsed.name == expected
    end
    for _, base in ipairs(searchDirs) do
        local cand = base .. "/" .. name
        if isFile(cand .. "/nar.json") and manifestNameMatches(cand, name) then
            return cand
        end
        if url ~= nil and url ~= "" then
            local cand2 = base .. "/" .. url
            if isFile(cand2 .. "/nar.json") and manifestNameMatches(cand2, name) then
                return cand2
            end
        end
    end
    return nil
end

---Discover every package directory reachable from the manifests under
---`roots` (transitive dependencies, read from the lunar cache). Returns
---a deduplicated list of package directories (newly added beyond the
---workspace roots themselves).
---@param roots string[]
---@return string[]
local function resolveDependencyDirs(roots)
    local searchDirs = {}
    for _, r in ipairs(roots) do searchDirs[#searchDirs + 1] = r end
    searchDirs[#searchDirs + 1] = expandHome("~/.nar")

    -- Start from every nar.json found anywhere under any workspace root.
    local manifestQueue = {}
    local seenManifest = {}
    for _, r in ipairs(roots) do
        for _, mpath in ipairs(scanManifests(r)) do
            if not seenManifest[mpath] then
                seenManifest[mpath] = true
                manifestQueue[#manifestQueue + 1] = mpath
            end
        end
    end

    local discoveredDirs = {}
    local seenPkg = {}

    local i = 1
    while i <= #manifestQueue do
        local mpath = manifestQueue[i]
        i = i + 1
        local text = readFile(mpath)
        if text ~= nil then
            local ok, parsed = pcall(Packages.parseJson, text)
            if ok and type(parsed) == "table" and type(parsed.dependencies) == "table" then
                for depName, depUrl in pairs(parsed.dependencies) do
                    if not seenPkg[depName] then
                        seenPkg[depName] = true
                        local depDir = locatePackageDir(depName, depUrl, searchDirs)
                        if depDir ~= nil then
                            discoveredDirs[#discoveredDirs + 1] = depDir
                            local depManifest = depDir .. "/nar.json"
                            if not seenManifest[depManifest] then
                                seenManifest[depManifest] = true
                                manifestQueue[#manifestQueue + 1] = depManifest
                            end
                        end
                    end
                end
            end
        end
    end
    return discoveredDirs
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

---Parse every `.nar` file under each declared dependency directory.
---Called after the initial workspace scan so we can resolve manifests
---against everything available locally.
---@param roots string[]
local function indexDependencies(roots)
    for _, dep in ipairs(resolveDependencyDirs(roots)) do
        for _, path in ipairs(scanNarFiles(dep)) do
            if docs[path] == nil then
                local content = readFile(path)
                if content ~= nil then
                    reparse(path, content)
                end
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
-- Typed-AST resolver (position-based)
-- ----------------------------------------------------------------------------

-- The typed AST carries binding information that the parser cannot: a
-- `TyLocal` knows its declaring pattern, a `TyGlobal` knows the resolved
-- module + definition name, a `TyConstructor` knows its data type, and so
-- on. We walk the typed module to find the innermost expression / pattern
-- whose location contains the cursor, then map that node to a symbol the
-- rest of the LSP can hand back to the client.

---@param loc Location|nil
---@param offset integer
---@return boolean
local function locContainsOffset(loc, offset)
    if loc == nil or loc.start == nil or loc.finish == nil then return false end
    -- Treat the end as inclusive of one extra byte so the cursor sitting
    -- right after the last char of a token still hits it.
    return loc.start <= offset and offset <= loc.finish
end

---Smaller location = "more specific" hit; prefer deeper matches.
---@param a Location
---@param b Location
---@return boolean true if a is a tighter (smaller) match than b
local function tighter(a, b)
    return (a.finish - a.start) < (b.finish - b.start)
end

-- Forward declarations.
local visitExpr, visitPattern

---@param node table|nil
---@param offset integer
---@param best table  -- { node?, kind? } updated in-place with the best hit
local function visitNode(node, offset, best)
    if node == nil then return end
    local loc = node.location
    if not locContainsOffset(loc, offset) then return end
    if best.node == nil or tighter(loc, best.node.location) then
        best.node = node
    end
    -- Descend into children.
    local k = node.kind
    if k == nil then return end
    -- Expression kinds
    if     k == "TyApply" then
        visitNode(node.func, offset, best)
        for _, a in ipairs(node.args or {}) do visitNode(a, offset, best) end
    elseif k == "TyCall" then
        for _, a in ipairs(node.args or {}) do visitNode(a, offset, best) end
    elseif k == "TyConstructor" then
        for _, a in ipairs(node.args or {}) do visitNode(a, offset, best) end
    elseif k == "TyAccess" then
        visitNode(node.record, offset, best)
    elseif k == "TyLet" then
        visitNode(node.pattern, offset, best)
        visitNode(node.value, offset, best)
        visitNode(node.body, offset, best)
    elseif k == "TyList" then
        for _, it in ipairs(node.items or {}) do visitNode(it, offset, best) end
    elseif k == "TyTuple" then
        for _, it in ipairs(node.items or {}) do visitNode(it, offset, best) end
    elseif k == "TyRecord" then
        for _, f in ipairs(node.fields or {}) do
            -- TyRecordField has its own location covering "name = value"
            if locContainsOffset(f.location, offset) then
                if best.node == nil or tighter(f.location, best.node.location) then
                    best.node = { kind = "TyRecordFieldDecl", location = f.location,
                                  fieldName = f.name }
                end
                visitNode(f.value, offset, best)
            end
        end
    elseif k == "TyUpdate" then
        for _, f in ipairs(node.fields or {}) do
            if locContainsOffset(f.location, offset) then
                if best.node == nil or tighter(f.location, best.node.location) then
                    best.node = { kind = "TyRecordFieldDecl", location = f.location,
                                  fieldName = f.name }
                end
                visitNode(f.value, offset, best)
            end
        end
    elseif k == "TySelect" then
        visitNode(node.condition, offset, best)
        for _, c in ipairs(node.cases or {}) do
            if locContainsOffset(c.location, offset) then
                visitNode(c.pattern, offset, best)
                visitNode(c.expression, offset, best)
            end
        end
    -- Pattern kinds
    elseif k == "TyPAlias" then
        visitNode(node.nested, offset, best)
    elseif k == "TyPCons" then
        visitNode(node.head, offset, best)
        visitNode(node.tail, offset, best)
    elseif k == "TyPList" then
        for _, it in ipairs(node.items or {}) do visitNode(it, offset, best) end
    elseif k == "TyPTuple" then
        for _, it in ipairs(node.items or {}) do visitNode(it, offset, best) end
    elseif k == "TyPOption" then
        for _, a in ipairs(node.args or {}) do visitNode(a, offset, best) end
    elseif k == "TyPRecord" then
        for _, f in ipairs(node.fields or {}) do
            if locContainsOffset(f.location, offset) then
                if best.node == nil or tighter(f.location, best.node.location) then
                    best.node = { kind = "TyPRecordFieldDecl", location = f.location,
                                  fieldName = f.name }
                end
            end
        end
    end
    -- TyLocal / TyGlobal / TyConst / TyPNamed / TyPAny / TyPConst: leaves.
end

---Walk a typed module looking for the innermost node containing `offset`
---in the file at `path`.
---@param typedModule table
---@param path string
---@param offset integer
---@return table|nil node          the innermost typed node hit
---@return table|nil enclosingDef  the TypedDefinition whose body contains it
local function findNodeAt(typedModule, path, offset)
    if typedModule == nil then return nil, nil end
    local best = { node = nil }
    local enclosingDef = nil
    for _, d in ipairs(typedModule.definitions or {}) do
        if d.location and d.location.filePath == path
           and locContainsOffset(d.location, offset) then
            enclosingDef = d
            -- Look in the param patterns first, then the body.
            for _, p in ipairs(d.params or {}) do
                visitNode(p, offset, best)
            end
            visitNode(d.body, offset, best)
            -- Also catch hits on the def name itself.
            if d.nameLocation and locContainsOffset(d.nameLocation, offset) then
                if best.node == nil or tighter(d.nameLocation, best.node.location) then
                    best.node = { kind = "TyDefName", location = d.nameLocation,
                                  definition = d, moduleName = typedModule.name }
                end
            end
        end
    end
    return best.node, enclosingDef
end

---Translate a typed-AST hit into a `SymbolEntry` from `allSymbols()`,
---which the existing hover / definition / references handlers can render.
---Returns nil if the node has no resolvable target (e.g. a literal).
---@param node table
---@return SymbolEntry|nil
---@return table|nil localPattern  for TyLocal -- pattern in same file
local function nodeToSymbol(node)
    if node == nil then return nil end
    local k = node.kind

    if k == "TyGlobal" then
        -- Find the symbol by qualified name.
        local fqn = node.moduleName .. "." .. node.definitionName
        local matches = lookupSymbol(fqn, node.moduleName)
        return matches[1]
    end

    if k == "TyLocal" then
        -- Local binding: target is a TypedPattern in the same file.
        -- We don't have a SymbolEntry for it; return a synthetic entry.
        local target = node.target
        if target == nil then return nil end
        local loc = target.location
        if loc == nil then return nil end
        return {
            name = tostring(node.name),
            moduleName = "(local)",
            path = loc.filePath,
            kind = "local",
            hidden = false,
            doc = nil,
            location = loc,
            fullLocation = loc,
            raw = target,
        }, target
    end

    if k == "TyPNamed" or k == "TyPAlias" then
        -- Pattern that declares a local binding: clicking on the
        -- declaration itself hovers/jumps to itself.
        local loc = node.location
        local name = (k == "TyPNamed") and node.name or node.alias
        return {
            name = tostring(name),
            moduleName = "(local)",
            path = loc.filePath,
            kind = "local",
            hidden = false,
            doc = nil,
            location = loc,
            fullLocation = loc,
            raw = node,
        }, node
    end

    if k == "TyConstructor" or k == "TyPOption" then
        -- dataName is "Module.TypeName"; optionName is the variant.
        local dataName = node.dataName
        local optionName = node.optionName or (node.definition and node.definition.name)
        if dataName == nil or optionName == nil then return nil end
        local modName, typeName = dataName:match("^(.+)%.([^%.]+)$")
        if modName == nil then return nil end
        -- Find the type, then the option inside it.
        for _, sym in ipairs(allSymbols()) do
            if sym.kind == "constructor"
               and sym.moduleName == modName
               and sym.parentType == typeName
               and sym.name == optionName then
                return sym
            end
        end
        return nil
    end

    if k == "TyDefName" then
        local d = node.definition
        for _, sym in ipairs(allSymbols()) do
            if sym.moduleName == node.moduleName and sym.name == d.name
               and (sym.kind == "def" or sym.kind == "infix") then
                return sym
            end
        end
        return nil
    end

    -- TyAccess / TyRecordFieldDecl / TyPRecordFieldDecl have no top-level
    -- symbol to navigate to today; we may add field-resolution later.
    return nil
end

---Convenience: resolve a cursor position to its symbol via the typed AST.
---Returns nil if the file isn't parseable or no typed node covers the
---cursor (caller can fall back to name-based lookup).
---@param path string
---@param offset integer
---@return SymbolEntry|nil sym
---@return table|nil localPatternIfLocal
local function resolveAt(path, offset)
    ensureTyped()
    local entry = docs[path]
    if entry == nil or entry.parsedModule == nil then return nil end
    local tm = typedCache[entry.parsedModule.name]
    if tm == nil then return nil end
    local node = findNodeAt(tm, path, offset)
    if node == nil then return nil end
    local sym, localPat = nodeToSymbol(node)
    return sym, localPat, node
end

---Find every usage of a definition (or local) across the workspace by
---walking the typed AST and comparing resolved targets rather than text.
---@param target SymbolEntry
---@return table[] locations  list of LSP Location objects
local function findReferences(target)
    ensureTyped()
    local out = {}
    local function add(loc)
        local r = locToRange(loc)
        if r ~= nil then
            out[#out + 1] = { uri = pathToUri(loc.filePath), range = r }
        end
    end

    -- Local binding: scan only the file containing the pattern.
    if target.kind == "local" then
        local entry = docs[target.path]
        local tm
        if entry ~= nil and entry.parsedModule ~= nil then
            tm = typedCache[entry.parsedModule.name]
        end
        if tm == nil then return out end
        local pat = target.raw
        local function walk(n)
            if n == nil then return end
            if n.kind == "TyLocal" and n.target == pat then add(n.location) end
            -- Reuse visitNode's child-descent by hand; but simpler to
            -- inline a generic walker:
            for _, k in ipairs({ "func","record","value","body","head","tail",
                                 "nested","condition","pattern","expression" }) do
                if n[k] ~= nil then walk(n[k]) end
            end
            for _, list in ipairs({ "args","items","fields","cases","params" }) do
                if n[list] ~= nil then
                    for _, c in ipairs(n[list]) do walk(c) end
                end
            end
        end
        for _, d in ipairs(tm.definitions or {}) do
            for _, p in ipairs(d.params or {}) do walk(p) end
            walk(d.body)
        end
        -- Always include the declaration site itself.
        add(pat.location)
        return out
    end

    -- Global symbol: scan every typed module.
    local fqnModule = target.moduleName
    local fqnName   = target.name
    local function walk(n)
        if n == nil then return end
        if n.kind == "TyGlobal"
           and n.moduleName == fqnModule
           and n.definitionName == fqnName then
            add(n.location)
        elseif (n.kind == "TyConstructor" or n.kind == "TyPOption")
               and target.kind == "constructor"
               and n.dataName
               and n.dataName == fqnModule .. "." .. (target.parentType or "")
               and (n.optionName == fqnName
                    or (n.definition and n.definition.name == fqnName)) then
            add(n.location)
        end
        for _, k in ipairs({ "func","record","value","body","head","tail",
                             "nested","condition","pattern","expression" }) do
            if n[k] ~= nil then walk(n[k]) end
        end
        for _, list in ipairs({ "args","items","fields","cases","params" }) do
            if n[list] ~= nil then
                for _, c in ipairs(n[list]) do walk(c) end
            end
        end
    end
    for _, tm in pairs(typedCache) do
        for _, d in ipairs(tm.definitions or {}) do
            for _, p in ipairs(d.params or {}) do walk(p) end
            walk(d.body)
        end
    end
    -- Always include the declaration site itself.
    if target.location then add(target.location) end
    return out
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
    if sym.kind == "local" then
        -- Render the binding pattern with its inferred type.
        local pat = sym.raw
        local typeText = (pat and pat.type_ and pat.type_.code) and pat.type_:code("") or "?"
        return sym.name .. " : " .. typeText
    end
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
    if sym.kind ~= "local" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "_from `" .. sym.moduleName .. "`_"
    end
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
    -- Resolve dependencies declared in any workspace `nar.json` and index
    -- their source files too (e.g. `~/.nar/<repo>/...`). Otherwise hover /
    -- definition can't see anything outside the user's own packages.
    indexDependencies(roots)

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

    -- Prefer typed-AST resolution (knows about local bindings, scopes,
    -- and qualified references). Fall back to name-based lookup if the
    -- file isn't typeable (mid-edit / parse errors).
    local sym = resolveAt(path, offset)
    if sym ~= nil then return makeHover(sym) end

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

    -- Typed AST first.
    local sym = resolveAt(path, offset)
    if sym ~= nil then
        local loc = sym.fullLocation or sym.location
        local r = locToRange(loc)
        if r ~= nil then
            return { { uri = pathToUri(sym.path), range = r } }
        end
    end

    local word = wordAtOffset(entry.text, offset)
    if word == nil then return Json.EMPTY_ARRAY end
    local prefer = entry.parsedModule and entry.parsedModule.name or nil
    local matches = lookupSymbol(word, prefer)
    local locs = {}
    for _, s in ipairs(matches) do
        local r = locToRange(s.fullLocation or s.location)
        if r ~= nil then
            locs[#locs + 1] = { uri = pathToUri(s.path), range = r }
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

    -- Typed AST first: resolves to exactly the right binding/global and
    -- collects every reference to *that* target across the workspace.
    local sym = resolveAt(path, offset)
    if sym ~= nil then
        local locs = findReferences(sym)
        if #locs > 0 then return locs end
    end

    -- Fallback: legacy text-based search.
    local word = wordAtOffset(entry.text, offset)
    if word == nil then return Json.EMPTY_ARRAY end
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
