---LSP framing on top of stdio.
---
---Reads `Content-Length:`-framed JSON-RPC messages from stdin and
---writes them back to stdout. Both streams are switched to binary
---mode so CR/LF survives intact on Windows.

local Json = require("lunar.lsp.json")

local Transport = {}

---Configure stdio for binary, line-unbuffered transport. Must be
---called before the read/write loop starts.
function Transport.setup()
    io.stdin:setvbuf("no")
    io.stdout:setvbuf("no")
    io.stderr:setvbuf("line")
end

---Read a single LSP message and return the decoded payload, or `nil`
---on EOF.
---@return table|nil
function Transport.read()
    local headers = {}
    while true do
        local line = io.stdin:read("*l")
        if line == nil then return nil end
        -- Strip an optional trailing \r left in `*l` on some platforms.
        line = line:gsub("\r$", "")
        if line == "" then break end
        local name, value = line:match("^([^:]+):%s*(.+)$")
        if name then
            headers[name:lower()] = value
        end
    end
    local lenStr = headers["content-length"]
    if lenStr == nil then return nil end
    local len = tonumber(lenStr)
    if len == nil or len <= 0 then return nil end
    local body = io.stdin:read(len)
    if body == nil then return nil end
    local ok, payload = pcall(Json.decode, body)
    if not ok then
        io.stderr:write("lsp: malformed JSON body (" .. tostring(payload) .. ")\n")
        return nil
    end
    return payload
end

---Write a single LSP message to stdout.
---@param payload table
function Transport.write(payload)
    local body = Json.encode(payload)
    -- LSP requires UTF-8 byte length for Content-Length.
    io.stdout:write("Content-Length: " .. #body .. "\r\n\r\n")
    io.stdout:write(body)
    io.stdout:flush()
end

return Transport
