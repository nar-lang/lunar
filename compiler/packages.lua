---Package dependency resolver (pure).
---
---Walks the dependency graph declared in each package's `nar.json` and
---returns a deduplicated, dependency-first list of:
---  * `.nar` source file paths, and
---  * native Lua script paths (each already pointing at a `.lua` file
---    such as `<pkgDir>/init.lua`).
---
---`Packages.collect` performs no IO. Every package lookup is delegated
---to a `loadPackage(name, url)` callback supplied by the caller. The
---CLI provides a filesystem + git-clone implementation; an engine
---embedding can supply an in-memory / blob-backed loader.
---
---`loadPackage(name, url)`:
---  * `name` — the dependency's name as it appears in the parent's
---    `nar.json` (or one of the root names passed to `collect`);
---  * `url`  — the parent's declared repository URL for the dependency,
---    or `nil` for root names.
---  * returns `(moduleFiles, nativeScripts, narJsonText)` on success,
---    where `moduleFiles` and `nativeScripts` are string arrays
---    (possibly empty) and `narJsonText` is the raw `nar.json` source.
---    The resolver parses it (so callers don't need a JSON parser of
---    their own). On failure returns `(nil, nil, nil, err)`.
---  * Only `name` and `dependencies` are consulted from the manifest.
---    `dependencies` must be `{ [name: string]: url: string }`.
---
---Packages are deduplicated by their declared `name`; each declared
---name is loaded at most once even if multiple parents reference it
---under different aliases or URLs.

local Packages = {}

-- ----------------------------------------------------------------------------
-- Minimal JSON parser (subset sufficient for nar.json manifests).
-- ----------------------------------------------------------------------------

---@param text string
---@return any|nil value, string|nil err
local function jsonParse(text)
    local i = 1
    local n = #text

    local skipWs, parseValue, parseString, parseArray, parseObject, parseNumber

    skipWs = function()
        while i <= n do
            local c = text:sub(i, i)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                i = i + 1
            else
                return
            end
        end
    end

    local function err(msg)
        error("at offset " .. i .. ": " .. msg, 0)
    end

    parseString = function()
        if text:sub(i, i) ~= '"' then err("expected string") end
        i = i + 1
        local out = {}
        while i <= n do
            local c = text:sub(i, i)
            if c == '"' then
                i = i + 1
                return table.concat(out)
            elseif c == "\\" then
                i = i + 1
                local esc = text:sub(i, i)
                i = i + 1
                if esc == '"' then out[#out + 1] = '"'
                elseif esc == '\\' then out[#out + 1] = '\\'
                elseif esc == '/' then out[#out + 1] = '/'
                elseif esc == 'n' then out[#out + 1] = '\n'
                elseif esc == 't' then out[#out + 1] = '\t'
                elseif esc == 'r' then out[#out + 1] = '\r'
                elseif esc == 'b' then out[#out + 1] = '\b'
                elseif esc == 'f' then out[#out + 1] = '\f'
                elseif esc == 'u' then
                    local cp = tonumber(text:sub(i, i + 3), 16)
                    if cp == nil then err("bad \\u escape") end
                    i = i + 4
                    out[#out + 1] = utf8.char(cp)
                else err("bad escape \\" .. esc) end
            else
                out[#out + 1] = c
                i = i + 1
            end
        end
        err("unterminated string")
    end

    parseArray = function()
        i = i + 1
        skipWs()
        local arr = {}
        if text:sub(i, i) == "]" then i = i + 1; return arr end
        while true do
            arr[#arr + 1] = parseValue()
            skipWs()
            local c = text:sub(i, i)
            if c == "," then i = i + 1; skipWs()
            elseif c == "]" then i = i + 1; return arr
            else err("expected , or ]") end
        end
    end

    parseObject = function()
        i = i + 1
        skipWs()
        local obj = {}
        if text:sub(i, i) == "}" then i = i + 1; return obj end
        while true do
            skipWs()
            local key = parseString()
            skipWs()
            if text:sub(i, i) ~= ":" then err("expected :") end
            i = i + 1
            skipWs()
            obj[key] = parseValue()
            skipWs()
            local c = text:sub(i, i)
            if c == "," then i = i + 1
            elseif c == "}" then i = i + 1; return obj
            else err("expected , or }") end
        end
    end

    parseNumber = function()
        local s = i
        if text:sub(i, i) == "-" then i = i + 1 end
        while i <= n and text:sub(i, i):match("[%d%.eE%+%-]") do
            i = i + 1
        end
        local num = tonumber(text:sub(s, i - 1))
        if num == nil then err("bad number") end
        return num
    end

    parseValue = function()
        skipWs()
        local c = text:sub(i, i)
        if c == '"' then return parseString() end
        if c == "{" then return parseObject() end
        if c == "[" then return parseArray() end
        if c == "t" then
            if text:sub(i, i + 3) ~= "true" then err("expected true") end
            i = i + 4; return true
        end
        if c == "f" then
            if text:sub(i, i + 4) ~= "false" then err("expected false") end
            i = i + 5; return false
        end
        if c == "n" then
            if text:sub(i, i + 3) ~= "null" then err("expected null") end
            i = i + 4; return nil
        end
        if c == "-" or (c >= "0" and c <= "9") then return parseNumber() end
        err("unexpected character `" .. c .. "`")
    end

    local ok, result = pcall(parseValue)
    if not ok then return nil, tostring(result) end
    return result
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

---@alias LoadPackageFn fun(name: string, url: string|nil): string[]|nil, string[]|nil, string|nil, string|nil

---Resolve `packageNames` and their transitive dependencies via
---`loadPackage`. Returns flattened, dep-first, deduped lists of `.nar`
---source files and native Lua script paths.
---@param packageNames string[]
---@param loadPackage LoadPackageFn
---@return string[]|nil moduleFiles
---@return string[]|nil nativeScripts
---@return string|nil err
function Packages.collect(packageNames, loadPackage)
    if type(packageNames) ~= "table" then
        return nil, nil, "packages.collect: packageNames must be a table"
    end
    if type(loadPackage) ~= "function" then
        return nil, nil, "packages.collect: loadPackage must be a function"
    end

    -- Entry produced by loadPackage; cached by declared name and also
    -- by the lookup name (alias) it was first requested under.
    ---@class _PkgEntry
    ---@field name string                       declared name (from nar.json)
    ---@field modules string[]                  .nar source paths
    ---@field natives string[]                  native Lua script paths
    ---@field deps table<string, string>        name -> url

    local loaded = {}    -- lookup-name|declared-name -> _PkgEntry
    local appended = {}  -- declared-name -> true (in `ordered`)
    local visiting = {}  -- declared-name -> true (in-progress, cycle break)
    local ordered = {}   -- _PkgEntry[] in dep-first order

    local visit

    ---@param name string
    ---@param url string|nil
    ---@return string|nil err
    visit = function(name, url)
        local entry = loaded[name]
        if entry == nil then
            local modules, natives, narJsonText, lerr = loadPackage(name, url)
            if lerr ~= nil then
                return "package `" .. name .. "`: " .. lerr
            end
            if type(narJsonText) ~= "string" then
                return "package `" .. name ..
                    "`: loadPackage did not return nar.json text"
            end
            local narJson, perr = jsonParse(narJsonText)
            if narJson == nil then
                return "package `" .. name ..
                    "`: parse nar.json: " .. tostring(perr)
            end
            if type(narJson) ~= "table" then
                return "package `" .. name ..
                    "`: nar.json root must be an object"
            end
            local declared = narJson.name
            if type(declared) ~= "string" or declared == "" then
                return "package `" .. name ..
                    "`: nar.json is missing a string `name`"
            end

            local deps = narJson.dependencies
            if deps == nil then
                deps = {}
            elseif type(deps) ~= "table" then
                return "package `" .. declared ..
                    "`: `dependencies` must be an object"
            end

            entry = loaded[declared]
            if entry == nil then
                entry = {
                    name    = declared,
                    modules = modules or {},
                    natives = natives or {},
                    deps    = deps,
                }
                loaded[declared] = entry
            end
            if name ~= declared then
                loaded[name] = entry
            end
        end

        if appended[entry.name] then return nil end
        if visiting[entry.name] then return nil end -- cycle: skip back-edge
        visiting[entry.name] = true

        for depName, depUrl in pairs(entry.deps) do
            if type(depName) ~= "string" then
                return "package `" .. entry.name ..
                    "`: dependency keys must be strings"
            end
            if depUrl ~= nil and type(depUrl) ~= "string" then
                return "package `" .. entry.name ..
                    "`: dependency `" .. depName .. "` url must be a string"
            end
            local derr = visit(depName, depUrl)
            if derr ~= nil then return derr end
        end

        visiting[entry.name] = nil
        appended[entry.name] = true
        ordered[#ordered + 1] = entry
        return nil
    end

    for _, name in ipairs(packageNames) do
        if type(name) ~= "string" or name == "" then
            return nil, nil, "packages.collect: packageNames entries must be non-empty strings"
        end
        local err = visit(name, nil)
        if err ~= nil then return nil, nil, err end
    end

    -- Flatten dep-first, dedup by path.
    local moduleFiles, nativeScripts = {}, {}
    local seenMod, seenNat = {}, {}
    for _, entry in ipairs(ordered) do
        for _, f in ipairs(entry.modules) do
            if not seenMod[f] then
                seenMod[f] = true
                moduleFiles[#moduleFiles + 1] = f
            end
        end
        for _, n in ipairs(entry.natives) do
            if not seenNat[n] then
                seenNat[n] = true
                nativeScripts[#nativeScripts + 1] = n
            end
        end
    end

    return moduleFiles, nativeScripts
end

---Minimal JSON parser, exposed so loaders that need to peek at a
---manifest (e.g. to decide whether a candidate directory holds the
---expected package) don't have to ship their own.
Packages.parseJson = jsonParse

return Packages
