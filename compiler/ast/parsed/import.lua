local Statement = require("compiler.ast.parsed.defines").Statement

---@class Import : Statement
---@field kind "Import"
---@field location Location
---@field moduleIdentifier QualifiedIdentifier
---@field alias Identifier|nil
---@field exposingAll boolean
---@field exposing (Identifier|InfixIdentifier)[]
local Import = setmetatable({}, { __index = Statement })
Import.__index = Import

---@param location Location
---@param moduleIdentifier QualifiedIdentifier
---@param alias Identifier|nil
---@param exposingAll boolean
---@param exposing (Identifier|InfixIdentifier)[]
---@return Import
function Import.new(location, moduleIdentifier, alias, exposingAll, exposing)
    return setmetatable({
        kind = "Import",
        location = location,
        moduleIdentifier = moduleIdentifier,
        alias = alias,
        exposingAll = exposingAll == true,
        exposing = exposing or {},
    }, Import)
end

---@param name string
---@return boolean
function Import:exposes(name)
    if self.exposingAll then
        return true
    end
    for _, e in ipairs(self.exposing) do
        if e == name then
            return true
        end
    end
    return false
end

---@param f fun(stmt: Statement)
function Import:iterate(f)
    f(self)
end

---@return nil
---@return string
function Import:normalize()
    return nil, "TODO: normalize"
end

return { Import = Import }
