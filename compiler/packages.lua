---Package resolver.
---
---Given a list of search directories and a list of package names,
---returns:
---  * the set of all `.nar` source files belonging to the requested
---    packages and their transitive dependencies, in dependency-first
---    order;
---  * the set of directories that contain an `init.lua` native bridge
---    and so should be loaded as native modules (suitable for passing
---    straight to `--native PATH`, since CLI already appends
---    `/init.lua` to directory arguments).
---
---Lookup rules for a package (by `name`, plus optional `repo` URL
---when resolving a dependency):
---  1. `<searchDirs[i]>/<name>/nar.json` for each `i` in order;
---  2. `<searchDirs[i]>/<repo>/nar.json` for each `i` in order
---     (skipped if `repo` is nil — root names have no repo);
---  3. clone `https://<repo>` into `<searchDirs[1]>/<repo>` and load.
---
---`searchDirs[1]` doubles as the cache directory for clones; it is
---created (`mkdir -p`) if missing.
---
---No compilation is performed here; the returned file lists are the
---input to `Compiler.compile(sources, debug)`.

local Packages = {}

-- ----------------------------------------------------------------------------
-- Small IO / FS helpers (local; intentionally duplicated from cli/init.lua
-- so this module stays standalone — a later refactor can extract them).
-- ----------------------------------------------------------------------------

local function eprintln(s)
    io.stderr:write(s .. "\n")
end

---@param path string
---@return string|nil data, string|nil err
local function readAll(path)
    local f, err = io.open(path, "rb")
    if f == nil then return nil, err end
    local data = f:read("*a")
    f:close()
    return data
end

---@param path string
---@return string
local function dirname(path)
    local d = path:match("^(.*)/[^/]+$")
    return d or ""
end

---@param path string
---@return boolean
local function isDir(path)
    local cmd = 'test -d "' .. path:gsub('"', '\\"') .. '" && echo y || echo n'
    local p = io.popen(cmd)
    if p == nil then return false end
    local r = p:read("*l")
    p:close()
    return r == "y"
end

---@param path string
---@return boolean
local function isFile(path)
    local f = io.open(path, "rb")
    if f == nil then return false end
    f:close()
    return true
end

---@param cmd string
---@return string[]
local function findLines(cmd)
    local p = io.popen(cmd)
    if p == nil then return {} end
    local out = {}
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    table.sort(out)
    return out
end

-- ----------------------------------------------------------------------------
-- Minimal JSON parser (same subset as cli/init.lua)
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
-- PackageInfo loader (private)
-- ----------------------------------------------------------------------------

---@class PackageInfo
---@field name string                       declared name from nar.json
---@field repository string                 canonical repo URL (may be "")
---@field dependencies table<string,string> alias -> repo URL
---@field path string                       absolute or workspace-relative dir
---@field sources string[]                  every *.nar file under `path` (recursive)
---@field nativeDir string|nil              path if `init.lua` exists at root

---Load a `nar.json`-bearing directory into a PackageInfo. Returns
---`nil, err` if anything is wrong with the manifest.
---@param dir string
---@return PackageInfo|nil info, string|nil err
local function loadPackageInfo(dir)
    if not isDir(dir) then
        return nil, "not a directory: " .. dir
    end
    local manifestPath = dir .. "/nar.json"
    if not isFile(manifestPath) then
        return nil, "missing manifest: " .. manifestPath
    end
    local text, rerr = readAll(manifestPath)
    if text == nil then
        return nil, "read " .. manifestPath .. ": " .. tostring(rerr)
    end
    local parsed, perr = jsonParse(text)
    if parsed == nil then
        return nil, "parse " .. manifestPath .. ": " .. tostring(perr)
    end
    if type(parsed) ~= "table" then
        return nil, manifestPath .. ": root must be an object"
    end
    local name = parsed.name
    if type(name) ~= "string" or name == "" then
        return nil, manifestPath .. ": missing or invalid `name` (string)"
    end
    local repo = parsed.repository
    if repo ~= nil and type(repo) ~= "string" then
        return nil, manifestPath .. ": invalid `repository` (must be string)"
    end
    local deps = parsed.dependencies
    if deps == nil then
        deps = {}
    elseif type(deps) ~= "table" then
        return nil, manifestPath .. ": `dependencies` must be an object"
    end
    if #deps > 0 then
        return nil, manifestPath ..
            ": `dependencies` must be {name: repository} (got array)"
    end
    for k, v in pairs(deps) do
        if type(k) ~= "string" or type(v) ~= "string" then
            return nil, manifestPath ..
                ": `dependencies` entries must be string -> string"
        end
    end

    local quoted = dir:gsub('"', '\\"')
    local sources = findLines('find "' .. quoted .. '" -type f -name "*.nar" 2>/dev/null')

    local nativeDir = nil
    if isFile(dir .. "/init.lua") then
        nativeDir = dir
    end

    return {
        name = name,
        repository = repo or "",
        dependencies = deps,
        path = dir,
        sources = sources,
        nativeDir = nativeDir,
    }
end

---@param repoUrl string  e.g. github.com/nar-lang/Nar.Base
---@param destDir string
---@return string|nil err
local function cloneRepo(repoUrl, destDir)
    local parent = dirname(destDir)
    if parent ~= "" then
        os.execute('mkdir -p "' .. parent:gsub('"', '\\"') .. '"')
    end
    local quotedUrl = repoUrl:gsub('"', '\\"')
    local quotedDest = destDir:gsub('"', '\\"')
    eprintln("lunar: cloning " .. repoUrl .. " -> " .. destDir)
    local cmd = 'git clone --depth 1 "https://' .. quotedUrl .. '" "' ..
        quotedDest .. '" >&2'
    local ok = os.execute(cmd)
    if ok ~= true and ok ~= 0 then
        return "git clone failed for " .. repoUrl
    end
    return nil
end

---Probe a single candidate directory: if it contains a `nar.json`,
---load it and return the PackageInfo provided its declared name
---matches `expectedName`. Returns `nil, nil` when the directory is
---absent or the manifest does not match. Returns `nil, err` only on a
---real load failure.
---@param dir string
---@param expectedName string
---@return PackageInfo|nil info, string|nil err
local function tryLoad(dir, expectedName)
    if not isDir(dir) then return nil, nil end
    if not isFile(dir .. "/nar.json") then return nil, nil end
    local info, lerr = loadPackageInfo(dir)
    if info == nil then return nil, lerr end
    if info.name ~= expectedName then
        eprintln("lunar: warning: " .. dir ..
            "/nar.json declares name `" .. info.name ..
            "` but was looked up as `" .. expectedName .. "`")
        return nil, nil
    end
    return info
end

-- ----------------------------------------------------------------------------
-- Public API
-- ----------------------------------------------------------------------------

---Resolve `packageNames` against `searchDirs`, returning all `.nar`
---source files and all directories that should be loaded as native
---modules. `searchDirs[1]` is also used as the cache directory for
---clones triggered by transitive dependencies.
---
---@param searchDirs string[]     directories to search; the first is the cache
---@param packageNames string[]   names of packages to include
---@return string[]|nil moduleFiles  every `.nar` file across all resolved packages (dep-first, deduped)
---@return string[]|nil nativeDirs   directories containing `init.lua` for each resolved package (dep-first, deduped)
---@return string|nil err
function Packages.collect(searchDirs, packageNames)
    if type(searchDirs) ~= "table" or #searchDirs == 0 then
        return nil, nil, "packages.collect: searchDirs must be a non-empty list"
    end
    if type(packageNames) ~= "table" then
        return nil, nil, "packages.collect: packageNames must be a table"
    end

    local cacheDir = searchDirs[1]
    os.execute('mkdir -p "' .. cacheDir:gsub('"', '\\"') .. '"')

    -- name -> PackageInfo, populated lazily as we resolve.
    local known = {}

    ---Locate a package by `name` (and optional `repo`). Caches results.
    ---@param name string
    ---@param repo string|nil
    ---@return PackageInfo|nil info, string|nil err
    local function locate(name, repo)
        local cached = known[name]
        if cached ~= nil then return cached end

        -- 1) by package name in each search dir
        for _, base in ipairs(searchDirs) do
            local info, lerr = tryLoad(base .. "/" .. name, name)
            if lerr ~= nil then return nil, lerr end
            if info ~= nil then
                known[info.name] = info
                return info
            end
        end

        -- 2) by repo URL in each search dir
        if repo ~= nil and repo ~= "" then
            for _, base in ipairs(searchDirs) do
                local info, lerr = tryLoad(base .. "/" .. repo, name)
                if lerr ~= nil then return nil, lerr end
                if info ~= nil then
                    known[info.name] = info
                    return info
                end
            end

            -- 3) clone into the cache dir
            local destDir = cacheDir .. "/" .. repo
            local cerr = cloneRepo(repo, destDir)
            if cerr ~= nil then return nil, cerr end
            local info, lerr = loadPackageInfo(destDir)
            if info == nil then
                return nil, "dependency `" .. name .. "`: " .. lerr
            end
            if info.name ~= name then
                eprintln("lunar: warning: cloned `" .. repo ..
                    "` declares name `" .. info.name ..
                    "` but was requested as `" .. name .. "`")
            end
            known[info.name] = info
            return info
        end

        return nil, "package `" .. name ..
            "` not found in search dirs (no repository URL to clone from)"
    end

    local visited = {}      -- name -> true (resolution started)
    local ordered = {}      -- PackageInfo[] in dependency-first order

    local resolveOne -- forward decl

    ---@param info PackageInfo
    ---@return string|nil err
    resolveOne = function(info)
        if visited[info.name] then return nil end
        visited[info.name] = true
        for depName, depRepo in pairs(info.dependencies) do
            local depInfo, lerr = locate(depName, depRepo)
            if depInfo == nil then
                return "dependency `" .. depName .. "` of `" .. info.name ..
                    "`: " .. (lerr or "not found")
            end
            local rerr = resolveOne(depInfo)
            if rerr ~= nil then return rerr end
        end
        ordered[#ordered + 1] = info
        return nil
    end

    for _, name in ipairs(packageNames) do
        local info, lerr = locate(name, nil)
        if info == nil then return nil, nil, lerr end
        local rerr = resolveOne(info)
        if rerr ~= nil then return nil, nil, rerr end
    end

    -- Flatten: dep-first order, dedup source paths and native dirs.
    local moduleFiles, nativeDirs = {}, {}
    local seenSrc, seenNat = {}, {}
    for _, info in ipairs(ordered) do
        for _, f in ipairs(info.sources) do
            if not seenSrc[f] then
                seenSrc[f] = true
                moduleFiles[#moduleFiles + 1] = f
            end
        end
        if info.nativeDir ~= nil and not seenNat[info.nativeDir] then
            seenNat[info.nativeDir] = true
            nativeDirs[#nativeDirs + 1] = info.nativeDir
        end
    end

    return moduleFiles, nativeDirs
end

return Packages
