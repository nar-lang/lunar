---Tiny error channel shared by Execute and Runtime so a single sentinel
---table identifies interpreter-thrown errors. Raw Lua errors from buggy
---natives flow through as normal Lua errors and are wrapped at the apply
---boundary.

local Errors = {}

Errors.TAG = {}

---Raise a tagged Lua error caught by `Runtime:apply`.
---@param msg string
function Errors.throw(msg)
    error({ tag = Errors.TAG, msg = msg }, 0)
end

---@param e any
---@return boolean
function Errors.isOurs(e)
    return type(e) == "table" and e.tag == Errors.TAG
end

return Errors
