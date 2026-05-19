---@class Compiler
local Compiler = {}

---Callback signature for file loader function
---@alias FileGetCallback fun(content: string?, error: string?)

---File loader function type
---@alias FileLoader fun(path: string, callback: FileGetCallback)

---Compiles a source file using a custom file loader function
---@param path string The path to the file to compile
---@param get FileLoader File loader function
---@return string|nil compiled The compiled output as a byte string, or nil on error
---@return string|nil error Error message if compilation failed
function Compiler.compile(path, get)
    if type(path) ~= "string" then
        error("compile(path, get): path must be a string")
    end

    if type(get) ~= "function" then
        error("compile(path, get): get must be a function")
    end

    local done = false
    local source = nil
    local readError = nil

    get(path, function(content, err)
        done = true
        source = content
        readError = err
    end)

    if not done then
        error("compile(path, get): async callbacks are not supported yet")
    end

    if readError ~= nil then
        return nil, tostring(readError)
    end

    if type(source) ~= "string" then
        return nil, "compile(path, get): get callback must provide content as string"
    end

    -- Initial implementation: pass-through source bytes as the "compiled" blob.
    return source
end

return Compiler
