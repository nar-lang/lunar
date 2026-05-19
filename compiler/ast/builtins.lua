---Common identifiers shared between parsed/normalized/typed phases.

local misc = require("compiler.ast.misc")
local makeFullIdentifier = misc.makeFullIdentifier

---@type QualifiedIdentifier
local NAR_BASE_BASICS_NAME = "Nar.Base.Basics"
---@type QualifiedIdentifier
local NAR_BASE_MATH_NAME = "Nar.Base.Math"

---@type Identifier
local NAR_TRUE_NAME = "True"
---@type Identifier
local NAR_FALSE_NAME = "False"
---@type Identifier
local NAR_NEG_NAME = "neg"

---@type FullIdentifier
local NAR_BASE_BASICS_UNIT = makeFullIdentifier(NAR_BASE_BASICS_NAME, "Unit")
---@type FullIdentifier
local NAR_BASE_BASICS_BOOL = makeFullIdentifier(NAR_BASE_BASICS_NAME, "Bool")
---@type FullIdentifier
local NAR_BASE_MATH_INT = makeFullIdentifier(NAR_BASE_MATH_NAME, "Int")
---@type FullIdentifier
local NAR_BASE_MATH_FLOAT = makeFullIdentifier(NAR_BASE_MATH_NAME, "Float")
---@type FullIdentifier
local NAR_BASE_CHAR_CHAR = makeFullIdentifier("Nar.Base.Char", "Char")
---@type FullIdentifier
local NAR_BASE_STRING_STRING = makeFullIdentifier("Nar.Base.String", "String")
---@type FullIdentifier
local NAR_BASE_LIST_LIST = makeFullIdentifier("Nar.Base.List", "List")

---@param dataName FullIdentifier
---@param optionName Identifier
---@return DataOptionIdentifier
local function makeDataOptionIdentifier(dataName, optionName)
    return dataName .. "#" .. optionName
end

return {
    NAR_BASE_BASICS_NAME = NAR_BASE_BASICS_NAME,
    NAR_BASE_MATH_NAME = NAR_BASE_MATH_NAME,
    NAR_TRUE_NAME = NAR_TRUE_NAME,
    NAR_FALSE_NAME = NAR_FALSE_NAME,
    NAR_NEG_NAME = NAR_NEG_NAME,
    NAR_BASE_BASICS_UNIT = NAR_BASE_BASICS_UNIT,
    NAR_BASE_BASICS_BOOL = NAR_BASE_BASICS_BOOL,
    NAR_BASE_MATH_INT = NAR_BASE_MATH_INT,
    NAR_BASE_MATH_FLOAT = NAR_BASE_MATH_FLOAT,
    NAR_BASE_CHAR_CHAR = NAR_BASE_CHAR_CHAR,
    NAR_BASE_STRING_STRING = NAR_BASE_STRING_STRING,
    NAR_BASE_LIST_LIST = NAR_BASE_LIST_LIST,
    makeDataOptionIdentifier = makeDataOptionIdentifier,
}
