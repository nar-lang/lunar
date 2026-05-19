---@type QualifiedIdentifier
local NarBaseBasicsName = "Nar.Base.Basics"

---@type QualifiedIdentifier
local NarBaseMathName = "Nar.Base.Math"

---@type Identifier
local NarTrueName = "True"

---@type Identifier
local NarFalseName = "False"

---@type Identifier
local NarNegName = "neg"

---@param moduleName QualifiedIdentifier
---@param name Identifier
---@return FullIdentifier
local function makeFullIdentifier(moduleName, name)
    return moduleName .. "." .. name
end

---@param dataName FullIdentifier
---@param optionName Identifier
---@return DataOptionIdentifier
local function makeDataOptionIdentifier(dataName, optionName)
    return dataName .. "#" .. optionName
end

---@type FullIdentifier
local NarBaseCharChar = makeFullIdentifier("Nar.Base.Char", "Char")

---@type FullIdentifier
local NarBaseMathInt = makeFullIdentifier(NarBaseMathName, "Int")

---@type FullIdentifier
local NarBaseMathFloat = makeFullIdentifier(NarBaseMathName, "Float")

---@type FullIdentifier
local NarBaseBasicsUnit = makeFullIdentifier(NarBaseBasicsName, "Unit")

---@type FullIdentifier
local NarBaseStringString = makeFullIdentifier("Nar.Base.String", "String")

---@type FullIdentifier
local NarBaseListList = makeFullIdentifier("Nar.Base.List", "List")

---@type FullIdentifier
local NarBaseBasicsBool = makeFullIdentifier(NarBaseBasicsName, "Bool")

return {
    NarBaseBasicsName = NarBaseBasicsName,
    NarBaseMathName = NarBaseMathName,
    NarTrueName = NarTrueName,
    NarFalseName = NarFalseName,
    NarNegName = NarNegName,
    NarBaseCharChar = NarBaseCharChar,
    NarBaseMathInt = NarBaseMathInt,
    NarBaseMathFloat = NarBaseMathFloat,
    NarBaseBasicsUnit = NarBaseBasicsUnit,
    NarBaseStringString = NarBaseStringString,
    NarBaseListList = NarBaseListList,
    NarBaseBasicsBool = NarBaseBasicsBool,
    makeFullIdentifier = makeFullIdentifier,
    makeDataOptionIdentifier = makeDataOptionIdentifier,
}
