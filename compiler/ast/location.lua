local tokens = require("lunar.compiler.ast.tokens")
local SemanticToken = tokens.SemanticToken

---@class Location
---@field filePath    string
---@field fileContent string
---@field start       integer  byte offset (1-based) of the first byte
---@field finish      integer  byte offset (1-based, exclusive) of the last byte
---@field startLine   integer  1-based; 0 when start is out of range / empty
---@field startColumn integer  1-based codepoint column on startLine
---@field endLine     integer  1-based; 0 when finish is out of range / empty
---@field endColumn   integer  1-based codepoint column on endLine
local Location = {}
Location.__index = Location

-- Per-file index keyed by the content string. Lua interns strings, so two
-- Locations sharing the same source share a single entry. Weak-keyed so the
-- index disappears once the parser drops its reference to the source text.
---@type table<string, {lineStarts: integer[], cpColumn: integer[]}>
local _fileIndex = setmetatable({}, { __mode = "k" })

---@param content string
local function _indexFor(content)
    local idx = _fileIndex[content]
    if idx ~= nil then
        return idx
    end
    -- lineStarts[i] = byte offset of column 1 on line i.
    local lineStarts = { 1 }
    -- cpColumn[i] = codepoint column (1-based) of byte i within its line.
    -- Continuation bytes (10xxxxxx) carry the column of their leading byte.
    local cpColumn = {}
    local col = 1
    for i = 1, #content do
        local b = content:byte(i)
        cpColumn[i] = col
        if b == 10 then
            col = 1
            lineStarts[#lineStarts + 1] = i + 1
        elseif b < 0x80 or b >= 0xC0 then
            col = col + 1
        end
    end
    idx = { lineStarts = lineStarts, cpColumn = cpColumn }
    _fileIndex[content] = idx
    return idx
end

---Binary-search lineStarts for the line containing the 1-based byte `offset`.
---@param lineStarts integer[]
---@param offset integer
---@return integer line
local function _lineOf(lineStarts, offset)
    local lo, hi = 1, #lineStarts
    while lo < hi do
        local mid = (lo + hi + 1) // 2
        if lineStarts[mid] <= offset then
            lo = mid
        else
            hi = mid - 1
        end
    end
    return lo
end

---Resolve a byte `offset` against the per-file index. Returns (0, 0) when
---the offset is outside the file (e.g. cursor sentinel locations).
---@param content string
---@param offset integer
---@return integer line
---@return integer column
local function _resolve(content, offset)
    if content == "" or offset < 1 or offset > #content then
        return 0, 0
    end
    local idx = _indexFor(content)
    return _lineOf(idx.lineStarts, offset), idx.cpColumn[offset]
end

---@param filePath string
---@param content string
---@param start integer
---@param finish integer
---@return Location
function Location.new(filePath, content, start, finish)
    content = content or ""
    local startLine, startColumn = _resolve(content, start)
    local endLine, endColumn = _resolve(content, finish)
    return setmetatable({
        filePath = filePath,
        fileContent = content,
        start = start,
        finish = finish,
        startLine = startLine,
        startColumn = startColumn,
        endLine = endLine,
        endColumn = endColumn,
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
    return self.startLine, self.startColumn, self.endLine, self.endColumn
end

---@return string
function Location:cursorString()
    if self:isEmpty() then
        return ""
    end
    return string.format("%s:%d:%d", self.filePath, self.startLine, self.startColumn)
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
    local mod = 0
    for _, m in ipairs({ ... }) do
        mod = mod | m
    end
    return SemanticToken.new(self.startLine - 1, self.startColumn - 1, self:size(), type_, mod)
end

return { Location = Location }
