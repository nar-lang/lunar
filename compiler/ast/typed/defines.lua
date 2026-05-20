---@alias TypedLocalTypesMap table<Identifier, TypedType>

---@class TypedStatement
---@field kind string
---@field location Location
local TypedStatement = {}
TypedStatement.__index = TypedStatement

---Synthetic statement used as a placeholder owner of an `Equation` when
---the equation is *derived* during unification (e.g. from unifying two
---compound types whose operand locations don't sit inside the enclosing
---context). It carries only a `location` — LSP code should detect
---`kind == "SyntheticStmt"` and treat it as "no real source node".
---@class SyntheticStmt : TypedStatement
---@field kind "SyntheticStmt"
---@field location Location
local SyntheticStmt = setmetatable({}, { __index = TypedStatement })
SyntheticStmt.__index = SyntheticStmt

---@param loc Location
---@return SyntheticStmt
function SyntheticStmt.new(loc)
    return setmetatable({
        kind = "SyntheticStmt",
        location = loc,
    }, SyntheticStmt)
end

return {
    TypedStatement = TypedStatement,
    SyntheticStmt = SyntheticStmt,
}
