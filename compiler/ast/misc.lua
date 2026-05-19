---@alias Identifier string
---@alias QualifiedIdentifier string
---@alias InfixIdentifier string
---@alias FullIdentifier string
---@alias DataOptionIdentifier string

---@param id FullIdentifier
---@return QualifiedIdentifier
local function fullIdentifierModule(id)
    ---@type integer?
    local lastDot
    ---@type integer
    local i = 1
    while true do
        local s = id:find("%.", i, false)
        if s == nil then
            break
        end
        lastDot = s
        i = s + 1
    end
    if lastDot == nil then
        return id
    end
    return id:sub(1, lastDot - 1)
end

---@param ids FullIdentifier[]
---@param sep string
---@return string
local function joinFullIdentifiers(ids, sep)
    return table.concat(ids, sep)
end

---@param moduleName QualifiedIdentifier
---@param name Identifier
---@return FullIdentifier
local function makeFullIdentifier(moduleName, name)
    return moduleName .. "." .. name
end

return {
    fullIdentifierModule = fullIdentifierModule,
    joinFullIdentifiers = joinFullIdentifiers,
    makeFullIdentifier = makeFullIdentifier,
}
