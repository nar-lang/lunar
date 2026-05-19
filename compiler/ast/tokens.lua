---@alias SemanticTokenType integer
---@alias SemanticTokenModifier integer

local TokenType = {
    NAMESPACE = 0,
    TYPE = 1,
    CLASS = 2,
    ENUM = 3,
    INTERFACE = 4,
    STRUCT = 5,
    TYPE_PARAMETER = 6,
    PARAMETER = 7,
    VARIABLE = 8,
    PROPERTY = 9,
    ENUM_MEMBER = 10,
    EVENT = 11,
    FUNCTION = 12,
    METHOD = 13,
    MACRO = 14,
    KEYWORD = 15,
    MODIFIER = 16,
    COMMENT = 17,
    STRING = 18,
    NUMBER = 19,
    REGEXP = 20,
    OPERATOR = 21,
    DECORATOR = 22,
}

local TokenTypeLegend = {
    "namespace", "type", "class", "enum", "interface", "struct",
    "typeParameter", "parameter", "variable", "property", "enumMember",
    "event", "function", "method", "macro", "keyword", "modifier",
    "comment", "string", "number", "regexp", "operator", "decorator",
}

local TokenModifier = {
    DECLARATION = 0x001,
    DEFINITION = 0x002,
    READONLY = 0x004,
    STATIC = 0x008,
    DEPRECATED = 0x010,
    ABSTRACT = 0x020,
    ASYNC = 0x040,
    MODIFICATION = 0x080,
    DOCUMENTATION = 0x100,
    DEFAULT_LIBRARY = 0x200,
}

local TokenModifierLegend = {
    "declaration", "definition", "readonly", "static", "deprecated",
    "abstract", "async", "modification", "documentation", "defaultLibrary",
}

---@class SemanticToken
---@field line integer
---@field char integer
---@field length integer
---@field type SemanticTokenType
---@field modifiers SemanticTokenModifier
local SemanticToken = {}
SemanticToken.__index = SemanticToken

---@param line integer
---@param char integer
---@param length integer
---@param type_ SemanticTokenType
---@param modifiers SemanticTokenModifier
---@return SemanticToken
function SemanticToken.new(line, char, length, type_, modifiers)
    return setmetatable({
        line = line,
        char = char,
        length = length,
        type = type_,
        modifiers = modifiers or 0,
    }, SemanticToken)
end

return {
    TokenType = TokenType,
    TokenTypeLegend = TokenTypeLegend,
    TokenModifier = TokenModifier,
    TokenModifierLegend = TokenModifierLegend,
    SemanticToken = SemanticToken,
}
