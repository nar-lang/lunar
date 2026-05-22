---Internal helpers shared by lunar CLI verbs.
---Not part of the public API.

local M = {}

---@param s string
function M.eprintln(s)
    io.stderr:write(s .. "\n")
end

---@param path string
---@return string|nil data, string|nil err
function M.readAll(path)
    local f, err = io.open(path, "rb")
    if f == nil then
        return nil, err
    end
    local data = f:read("*a")
    f:close()
    return data
end

---@param path string
---@param data string
---@return boolean ok, string|nil err
function M.writeAll(path, data)
    local f, err = io.open(path, "wb")
    if f == nil then
        return false, err
    end
    f:write(data)
    f:close()
    return true
end

---Run a shell command and collect its output lines (sorted).
---@param cmd string
---@return string[]
function M.findLines(cmd)
    local p = io.popen(cmd)
    if p == nil then
        return {}
    end
    local out = {}
    for line in p:lines() do
        out[#out + 1] = line
    end
    p:close()
    table.sort(out)
    return out
end

---Expand a single positional argument into a list of `.nar` file paths.
---Accepts:
---  * a literal path (no glob meta);
---  * `<dir>/*` or `<dir>/*.nar` — every `.nar` file directly under `<dir>`;
---  * `<dir>/**/*` or `<dir>/**/*.nar` — every `.nar` file recursively.
---@param pat string
---@return string[]|nil files
---@return string|nil err
function M.expandArg(pat)
    if not pat:find("[*?]") then
        return { pat }
    end

    local dir = pat:match("^(.+)/%*%*/%*%.nar$") or pat:match("^(.+)/%*%*/%*$")
    if dir ~= nil then
        return M.findLines('find "' .. dir .. '" -type f -name "*.nar" 2>/dev/null')
    end

    dir = pat:match("^(.+)/%*%.nar$") or pat:match("^(.+)/%*$")
    if dir ~= nil then
        return M.findLines('find "' .. dir .. '" -maxdepth 1 -type f -name "*.nar" 2>/dev/null')
    end

    return nil, "unsupported glob pattern `" .. pat .. "` (use `dir/*` or `dir/**/*`)"
end

---Expand a list of positional patterns into a deduplicated, ordered list of
---existing `.nar` file paths. Returns `nil, err` on the first failure.
---`verbName` is used for error prefixes.
---@param verbName string
---@param positional string[]
---@return string[]|nil files
---@return string|nil err
function M.collectSources(verbName, positional)
    local seen = {}
    local files = {}
    for _, a in ipairs(positional) do
        local matched, gerr = M.expandArg(a)
        if matched == nil then
            return nil, verbName .. ": " .. gerr
        end
        if #matched == 0 then
            return nil, verbName .. ": no .nar files matched `" .. a .. "`"
        end
        for _, f in ipairs(matched) do
            if not seen[f] then
                seen[f] = true
                files[#files + 1] = f
            end
        end
    end
    return files
end

---Read all source files into a `path -> content` table.
---@param verbName string
---@param files string[]
---@return table<string, string>|nil sources
---@return string|nil err
function M.readSources(verbName, files)
    local sources = {}
    for _, path in ipairs(files) do
        local content, rerr = M.readAll(path)
        if content == nil then
            return nil, verbName .. ": read " .. path .. ": " .. tostring(rerr)
        end
        sources[path] = content
    end
    return sources
end

---Return the directory part of a path (no trailing slash). Empty string
---means the current directory.
---@param path string
---@return string
local function dirname(path)
    local d = path:match("^(.*)/[^/]+$")
    return d or ""
end

M.dirname = dirname

---Return the basename (last component) of a path.
---@param path string
---@return string
local function basename(path)
    return path:match("([^/]+)$") or path
end

M.basename = basename

---Walk up from `startDir` until a directory containing `marker` is found.
---Returns the package directory or `nil` if none found.
---@param startDir string
---@param marker string e.g. "nar.json"
---@return string|nil
function M.findPackageRoot(startDir, marker)
    local dir = startDir
    if dir == "" then dir = "." end
    -- Absolute or relative; loop until parent equals current (filesystem root).
    while true do
        local probe = dir .. "/" .. marker
        local f = io.open(probe, "rb")
        if f ~= nil then
            f:close()
            return dir
        end
        local parent = dir:match("^(.*)/[^/]+$")
        if parent == nil or parent == dir then
            return nil
        end
        if parent == "" then parent = "/" end
        dir = parent
    end
end

return M
