---@param ids FullIdentifier[]
---@param name InfixIdentifier
---@param loc Location
---@return string
local function newAmbiguousInfixError(ids, name, loc)
    if #ids == 0 then
        return string.format("infix definition `%s` not found", name)
    end
    return string.format(
        "ambiguous infix identifier `%s`, it can be one of %s. "
        .. "Use import to clarify which one to use",
        name,
        table.concat(ids, ", ")
    )
end

---@param ids FullIdentifier[]
---@param name QualifiedIdentifier
---@param loc Location
---@return string
local function newAmbiguousDefinitionError(ids, name, loc)
    if #ids == 0 then
        return string.format("definition `%s` not found", name)
    end
    return string.format(
        "ambiguous identifier `%s`, it can be one of %s. "
        .. "Use import or qualified identifer to clarify which one to use",
        name,
        table.concat(ids, ", ")
    )
end

return {
    newAmbiguousInfixError = newAmbiguousInfixError,
    newAmbiguousDefinitionError = newAmbiguousDefinitionError,
}
