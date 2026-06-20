---Prefix `msg` with `loc`'s `file:line:col` cursor string when available.
---No-op when `loc` is nil or empty.
---@param loc Location|nil
---@param msg string
---@return string
local function locErr(loc, msg)
    if loc == nil then return msg end
    if loc.isEmpty ~= nil and loc:isEmpty() then return msg end
    local cs = loc:cursorString()
    if cs == nil or cs == "" then return msg end
    return cs .. ": " .. msg
end

---@param ids FullIdentifier[]
---@param name InfixIdentifier
---@param loc Location
---@return string
local function newAmbiguousInfixError(ids, name, loc)
    if #ids == 0 then
        return locErr(loc, string.format("infix definition `%s` not found", name))
    end
    return locErr(loc, string.format(
        "ambiguous infix identifier `%s`, it can be one of %s. "
        .. "Use import to clarify which one to use",
        name,
        table.concat(ids, ", ")
    ))
end

---@param ids FullIdentifier[]
---@param name QualifiedIdentifier
---@param loc Location
---@return string
local function newAmbiguousDefinitionError(ids, name, loc)
    if #ids == 0 then
        return locErr(loc, string.format("definition `%s` not found", name))
    end
    return locErr(loc, string.format(
        "ambiguous identifier `%s`, it can be one of %s. "
        .. "Use import or qualified identifer to clarify which one to use",
        name,
        table.concat(ids, ", ")
    ))
end

---@generic K, V
---@param t table<K, V>
---@return table<K, V>
local function cloneMap(t)
    local r = {}
    for k, v in pairs(t) do
        r[k] = v
    end
    return r
end

return {
    locErr = locErr,
    newAmbiguousInfixError = newAmbiguousInfixError,
    newAmbiguousDefinitionError = newAmbiguousDefinitionError,
    cloneMap = cloneMap,
}
