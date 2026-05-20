local tokens = require("lunar.compiler.ast.tokens")
local SemanticToken = tokens.SemanticToken

---@class Location
---@field filePath string
---@field fileContent string
---@field start integer
---@field finish integer
local Location = {}
Location.__index = Location

---@param filePath string
---@param content string
---@param start integer
---@param finish integer
---@return Location
function Location.new(filePath, content, start, finish)
    return setmetatable({
        filePath = filePath,
        fileContent = content,
        start = start,
        finish = finish,
    }, Location)
end

---@param filePath string
---@param content string
---@param start integer
---@return Location
function Location.newCursor(filePath, content, start)
    return Location.new(filePath, content, start, start)
end

---@param other Location
---@return boolean
function Location:equals(other)
    return self.filePath == other.filePath
        and self.start == other.start
        and self.finish == other.finish
end

---@return boolean
function Location:isEmpty()
    return self.filePath == nil or self.filePath == ""
end

---@return integer startLine
---@return integer startColumn
---@return integer endLine
---@return integer endColumn
function Location:getLineAndColumn()
    local line = 1
    local column = 1
    local startLine, startColumn, endLine, endColumn = 0, 0, 0, 0
    local content = self.fileContent or ""

    -- The parser stores `start`/`finish` as byte offsets, but the Go reference
    -- iterates a []rune slice, so columns must count Unicode codepoints.
    -- Iterate every byte (so the offset comparison matches), but only advance
    -- the column when the current byte is a UTF-8 leading byte (i.e., not a
    -- 10xxxxxx continuation byte).
    for i = 1, #content do
        if i == self.start then
            startLine = line
            startColumn = column
        end
        if i == self.finish then
            endLine = line
            endColumn = column
        end
        local b = content:byte(i)
        if b == 10 then
            line = line + 1
            column = 1
        elseif b < 0x80 or b >= 0xC0 then
            column = column + 1
        end
    end
    return startLine, startColumn, endLine, endColumn
end

---@return string
function Location:cursorString()
    if self:isEmpty() then
        return ""
    end
    local line, col = self:getLineAndColumn()
    return string.format("%s:%d:%d", self.filePath, line, col)
end

---@return string
function Location:text()
    if self.fileContent == nil then
        return ""
    end
    return self.fileContent:sub(self.start, self.finish - 1)
end

---@param cursor Location
---@return boolean
function Location:contains(cursor)
    return self.start <= cursor.start and cursor.finish <= self.finish
end

---@return integer
function Location:size()
    return self.finish - self.start
end

---@param type_ SemanticTokenType
---@param ... SemanticTokenModifier
---@return SemanticToken
function Location:toToken(type_, ...)
    local line, col = self:getLineAndColumn()
    local mod = 0
    for _, m in ipairs({ ... }) do
        mod = mod | m
    end
    return SemanticToken.new(line - 1, col - 1, self:size(), type_, mod)
end

return { Location = Location }
