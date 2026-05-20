local treePrint = require("compiler.ast.parsed.tree_print")
---@alias NamedTypeMap table<FullIdentifier, NormType>

---@class Statement
---@field kind string
---@field location Location
local Statement = {}
Statement.__index = Statement

---Iterate this statement and its children. Concrete subclasses must override.
---@param f fun(stmt: Statement)
function Statement:iterate(f)
    error("abstract method 'iterate' not implemented for kind=" .. tostring(self.kind), 2)
end

---Render this node and all of its descendants as a single multi-line string.
---One line per node, indented with `\t * offset`.
---@param offset integer
---@return string
function Statement:stringTree(offset)
    return treePrint.stringTree(self, offset or 0)
end

---Merge variadic error lists into a single flat list. nil arguments are ignored.
---@param ... string[]|nil
---@return string[]
local function mergeErrors(...)
    local out = {}
    local n = select("#", ...)
    for i = 1, n do
        local errs = select(i, ...)
        if errs ~= nil then
            for _, e in ipairs(errs) do
                out[#out + 1] = e
            end
        end
    end
    return out
end

---Wrap a single optional error into the errors list shape.
---@param err string|nil
---@return string[]
local function singleError(err)
    if err == nil then
        return {}
    end
    return { err }
end

---Combine several optional error strings into a single optional error string
---(joined by `; `). Mirrors `common.MergeErrors(err1, err2, ...)` from Go.
---@param ... string|nil
---@return string|nil
local function joinErrors(...)
    local parts = {}
    local n = select("#", ...)
    for i = 1, n do
        local e = select(i, ...)
        if e ~= nil and e ~= "" then
            parts[#parts + 1] = e
        end
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts, "; ")
end

---Same as joinErrors, but accepts a list of errors.
---@param errs (string|nil)[]
---@return string|nil
local function joinErrorList(errs)
    return joinErrors(table.unpack(errs))
end

return {
    Statement = Statement,
    mergeErrors = mergeErrors,
    singleError = singleError,
    joinErrors = joinErrors,
    joinErrorList = joinErrorList,
}
