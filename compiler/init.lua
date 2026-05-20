---Compiler pipeline (Lua port).
---
---The high-level entry point is `Compiler.compile(sources, debug)` which
---runs the full pipeline. The individual stage functions below are also
---public so callers can drive compilation incrementally.
---
---Stages:
---   parse(fileName, content)                    -> ParsedModule|nil, errors[]
---   normalize(parsedModules, normalizedModules) -> errors[]
---   annotate(normalizedModules, typedModules)   -> errors[]
---   validate(typedModules)                      -> errors[]
---   link(typedModules, debug)                   -> bytes|nil, errors[]
---   compile(sources, debug)                     -> bytes|nil, errors[]
---
---Each "modules" map is keyed by qualified module name (e.g.
---"Nar.Base.Basics") and is mutated in place by the corresponding stage.
---Stages skip work that is already present in the output map, so callers
---can run them incrementally.

local Parser        = require("lunar.compiler.parser")
local BinaryMod     = require("lunar.compiler.bytecode.binary")
local BinaryHashMod = require("lunar.compiler.bytecode.binary_hash")

---@class Compiler
local Compiler      = {}

-- ----------------------------------------------------------------------------
-- parse
-- ----------------------------------------------------------------------------

---Parse a single source file into a ParsedModule.
---@param fileName string
---@param content  string
---@return table|nil module     ParsedModule on success, nil on failure
---@return string[]  errors
function Compiler.parse(fileName, content)
    if type(fileName) ~= "string" then
        error("parse(fileName, content): fileName must be a string")
    end
    if type(content) ~= "string" then
        error("parse(fileName, content): content must be a string")
    end
    local module, errors = Parser.parse(fileName, content)
    return module, errors or {}
end

-- ----------------------------------------------------------------------------
-- normalize
-- ----------------------------------------------------------------------------

---Lower every parsed module's data types, expand imports, then normalize.
---Mutates `normalizedModules` in place. Skips modules already present there.
---@param parsedModules     table<string, table>
---@param normalizedModules table<string, table>
---@return string[] errors
function Compiler.normalize(parsedModules, normalizedModules)
    if type(parsedModules) ~= "table" then
        error("normalize: parsedModules must be a table")
    end
    if type(normalizedModules) ~= "table" then
        error("normalize: normalizedModules must be a table")
    end

    -- Iterate in sorted order for deterministic error reporting.
    local names = {}
    for n in pairs(parsedModules) do names[#names + 1] = n end
    table.sort(names)

    local errors = {}

    -- Generate (data-type lowering + import expansion) over every parsed
    -- module before normalizing any of them, mirroring the Go pipeline.
    for _, n in ipairs(names) do
        if normalizedModules[n] == nil then
            local errs = parsedModules[n]:generate(parsedModules)
            if errs ~= nil then
                for _, e in ipairs(errs) do errors[#errors + 1] = e end
            end
        end
    end

    for _, n in ipairs(names) do
        if normalizedModules[n] == nil then
            local errs = parsedModules[n]:normalize(parsedModules, normalizedModules)
            if errs ~= nil then
                for _, e in ipairs(errs) do errors[#errors + 1] = e end
            end
        end
    end

    return errors
end

-- ----------------------------------------------------------------------------
-- annotate
-- ----------------------------------------------------------------------------

---Annotate normalized modules into typed modules.
---Mutates `typedModules` in place. Skips modules already typed.
---@param normalizedModules table<string, table>
---@param typedModules      table<string, table>
---@return string[] errors
function Compiler.annotate(normalizedModules, typedModules)
    if type(normalizedModules) ~= "table" then
        error("annotate: normalizedModules must be a table")
    end
    if type(typedModules) ~= "table" then
        error("annotate: typedModules must be a table")
    end

    local names = {}
    for n in pairs(normalizedModules) do names[#names + 1] = n end
    table.sort(names)

    local errors = {}
    for _, n in ipairs(names) do
        if typedModules[n] == nil then
            local errs = normalizedModules[n]:annotate(normalizedModules, typedModules)
            if errs ~= nil then
                for _, e in ipairs(errs) do errors[#errors + 1] = e end
            end
        end
    end
    return errors
end

-- ----------------------------------------------------------------------------
-- validate
-- ----------------------------------------------------------------------------

---Run Hindley-Milner type-checking and pattern exhaustiveness checking on
---every typed module.
---@param typedModules table<string, table>
---@return string[] errors
function Compiler.validate(typedModules)
    if type(typedModules) ~= "table" then
        error("validate: typedModules must be a table")
    end

    local names = {}
    for n in pairs(typedModules) do names[#names + 1] = n end
    table.sort(names)

    local errors = {}
    for _, n in ipairs(names) do
        local tm = typedModules[n]
        local errs = tm:checkTypes()
        if errs ~= nil then
            for _, e in ipairs(errs) do errors[#errors + 1] = e end
        end
        errs = tm:checkPatterns()
        if errs ~= nil then
            for _, e in ipairs(errs) do errors[#errors + 1] = e end
        end
    end
    return errors
end

-- ----------------------------------------------------------------------------
-- link
-- ----------------------------------------------------------------------------

---Compose all typed modules into a single Binary and serialize it.
---@param typedModules table<string, table>
---@param debug boolean
---@return string|nil bytes  the serialized bytecode, or nil on error
---@return string[]  errors
function Compiler.link(typedModules, debug)
    if type(typedModules) ~= "table" then
        error("link: typedModules must be a table")
    end

    local names = {}
    for n in pairs(typedModules) do names[#names + 1] = n end
    table.sort(names)

    local binary = BinaryMod.Binary.new()
    local hash = BinaryHashMod.BinaryHash.new()
    local errors = {}

    for _, n in ipairs(names) do
        local err = typedModules[n]:compose(typedModules, debug, binary, hash)
        if err ~= nil then
            errors[#errors + 1] = tostring(err)
            return nil, errors
        end
    end

    return binary:build(debug), errors
end

-- ----------------------------------------------------------------------------
-- compile (full pipeline)
-- ----------------------------------------------------------------------------

---Run the full pipeline on a set of source files.
---
---`sources` is a map of `fileName -> content`. The file name is only used
---for diagnostics (parse error locations); the module's logical name comes
---from its `module X.Y where` declaration.
---
---On any stage error, returns `nil` and the accumulated errors so far.
---On success, returns the serialized bytecode bytes and an empty list.
---
---@param sources table<string, string>
---@param debug boolean
---@return string|nil bytes
---@return string[]   errors
function Compiler.compile(sources, debug)
    if type(sources) ~= "table" then
        error("compile(sources, debug): sources must be a {[fileName]=content} table")
    end

    local errors = {}
    local parsedModules = {}

    -- Sort file names for deterministic error ordering.
    local fileNames = {}
    for fileName in pairs(sources) do fileNames[#fileNames + 1] = fileName end
    table.sort(fileNames)

    for _, fileName in ipairs(fileNames) do
        local content = sources[fileName]
        if type(content) ~= "string" then
            error(string.format(
                "compile: sources[%q] must be a string", fileName))
        end

        local m, perrs = Compiler.parse(fileName, content)
        if perrs ~= nil then
            for _, e in ipairs(perrs) do errors[#errors + 1] = e end
        end
        if m ~= nil then
            if parsedModules[m.name] ~= nil then
                errors[#errors + 1] = string.format(
                    "module name collision: `%s`", tostring(m.name))
            else
                parsedModules[m.name] = m
            end
        end
    end

    if #errors > 0 then return nil, errors end

    local normalizedModules = {}
    local nerrs = Compiler.normalize(parsedModules, normalizedModules)
    for _, e in ipairs(nerrs) do errors[#errors + 1] = e end
    if #errors > 0 then return nil, errors end

    local typedModules = {}
    local aerrs = Compiler.annotate(normalizedModules, typedModules)
    for _, e in ipairs(aerrs) do errors[#errors + 1] = e end
    if #errors > 0 then return nil, errors end

    local verrs = Compiler.validate(typedModules)
    for _, e in ipairs(verrs) do errors[#errors + 1] = e end
    if #errors > 0 then return nil, errors end

    local bytes, lerrs = Compiler.link(typedModules, debug)
    for _, e in ipairs(lerrs) do errors[#errors + 1] = e end
    if bytes == nil then return nil, errors end

    return bytes, errors
end

return Compiler
