---Helpers for the normalized AST.

---@param expr NormExpression
---@param definedLocals NormPatternMap
---@param params NormPatternMap
---@return Identifier[]
local function extractUsedLocals(expr, definedLocals, params)
    ---@type table<Identifier, true>
    local usedLocals = {}
    expr:extractUsedLocalsSet(definedLocals, usedLocals)
    ---@type Identifier[]
    local uniqueLocals = {}
    for k in pairs(usedLocals) do
        if params[k] == nil then
            uniqueLocals[#uniqueLocals + 1] = k
        end
    end
    table.sort(uniqueLocals)
    return uniqueLocals
end

---@param params NormPattern[]
---@return NormPatternMap
local function extractParamNames(params)
    ---@type NormPatternMap
    local paramNames = {}
    for _, p in ipairs(params) do
        p:extractLocals(paramNames)
    end
    return paramNames
end

return {
    extractUsedLocals = extractUsedLocals,
    extractParamNames = extractParamNames,
}
