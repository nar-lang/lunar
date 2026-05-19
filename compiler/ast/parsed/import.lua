local Statement = require("compiler.ast.parsed.defines").Statement

---@class Import : Statement
---@field kind "Import"
---@field location Location
---@field moduleIdentifier QualifiedIdentifier
---@field alias Identifier|nil
---@field exposingAll boolean
---@field exposing (Identifier|InfixIdentifier)[]
local Import = setmetatable({}, { __index = Statement })
Import.__index = Import

---@param location Location
---@param moduleIdentifier QualifiedIdentifier
---@param alias Identifier|nil
---@param exposingAll boolean
---@param exposing (Identifier|InfixIdentifier)[]
---@return Import
function Import.new(location, moduleIdentifier, alias, exposingAll, exposing)
    return setmetatable({
        kind = "Import",
        location = location,
        moduleIdentifier = moduleIdentifier,
        alias = alias,
        exposingAll = exposingAll == true,
        exposing = exposing or {},
    }, Import)
end

---Reports whether this (unwrapped) import exposes `name`.
---After `unwrap`, `self.exposing` is the fully expanded list of exported names,
---so we just scan it; `exposingAll` is intentionally NOT consulted here because
---it would otherwise spuriously match names not actually defined in the target.
---@param name string
---@return boolean
function Import:exposes(name)
    for _, e in ipairs(self.exposing) do
        if e == name then
            return true
        end
    end
    return false
end

---@param f fun(stmt: Statement)
function Import:iterate(f)
    f(self)
end

---Expand `exposing` to a fully qualified list of names defined by the target module.
---Returns the expansion error (or nil on success). After unwrap, `exposes(name)`
---can be used to test whether the importer's module exports `name`.
---@param modules table<QualifiedIdentifier, Module>
---@return string|nil error
function Import:unwrap(modules)
    local TData = require("compiler.ast.parsed.type_data").TData

    local m = modules[self.moduleIdentifier]
    if m == nil then
        return string.format("module `%s` not found", self.moduleIdentifier)
    end

    local modName = m.name
    if self.alias ~= nil then
        modName = self.alias
    end
    assert(modName ~= nil)
    local modNameStr = tostring(modName)
    local shortModName = ""
    ---@type integer|nil
    local lastDot
    for i = #modNameStr, 1, -1 do
        if modNameStr:sub(i, i) == "." then
            lastDot = i
            break
        end
    end
    if lastDot ~= nil then
        shortModName = modNameStr:sub(lastDot + 1)
    end

    local exposingSet = {}
    if not self.exposingAll then
        for _, n in ipairs(self.exposing) do
            exposingSet[n] = true
        end
    end

    local exp = {}
    ---@param n string short name
    ---@param exn string name to test against the original exposing list
    local function expose(n, exn)
        if self.exposingAll or exposingSet[exn] then
            exp[#exp + 1] = n
        end
        exp[#exp + 1] = string.format("%s.%s", modNameStr, n)
        if shortModName ~= "" then
            exp[#exp + 1] = string.format("%s.%s", shortModName, n)
        end
    end

    for _, d in ipairs(m.definitions) do
        if not d.hidden then
            expose(d.name, d.name)
        end
    end

    for _, a in ipairs(m.aliases) do
        if not a.hidden then
            expose(a.name, a.name)
            local at = a:aliasType()
            if at ~= nil and getmetatable(at) == TData then
                ---@cast at TData
                for _, v in ipairs(at.options) do
                    if not v.hidden then
                        expose(v.name, a.name)
                    end
                end
            end
        end
    end

    for _, i in ipairs(m.infixFns) do
        if not i.hidden then
            expose(i.name, i.name)
        end
    end

    self.exposing = exp
    return nil
end

return { Import = Import }
