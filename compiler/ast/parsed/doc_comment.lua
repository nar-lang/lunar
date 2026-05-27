local Statement = require("lunar.compiler.ast.parsed.defines").Statement

---A doc comment block attached to the parsed entity that immediately
---follows it. Produced by the parser when it encounters one or more
---consecutive `///` line comments, or a single `/** ... */` block.
---Text is the cleaned-up Markdown body (leading `*`/whitespace stripped
---per line, leading/trailing blank lines trimmed).
---
---Doc comments do not survive normalization; their content is consumed
---by `Docs.collect` (see `lunar.compiler.docs`).
---@class DocComment : Statement
---@field kind "DocComment"
---@field location Location
---@field text string
local DocComment = setmetatable({}, { __index = Statement })
DocComment.__index = DocComment

---@param location Location
---@param text string
---@return DocComment
function DocComment.new(location, text)
    return setmetatable({
        kind = "DocComment",
        location = location,
        text = text,
    }, DocComment)
end

---@param f fun(stmt: Statement)
function DocComment:iterate(f)
    f(self)
end

return { DocComment = DocComment }
