local Statement = require("compiler.ast.parsed.defines").Statement

---@class Module : Statement
---@field kind "Module"
---@field name QualifiedIdentifier
---@field location Location
---@field packageName PackageIdentifier|nil
---@field referencedPackages PackageIdentifier[]
---@field imports Import[]
---@field aliases Alias[]
---@field infixFns Infix[]
---@field definitions Definition[]
---@field dataTypes DataType[]
local Module = setmetatable({}, { __index = Statement })
Module.__index = Module

---@param name QualifiedIdentifier
---@param location Location
---@param imports Import[]
---@param aliases Alias[]
---@param infixFns Infix[]
---@param definitions Definition[]
---@param dataTypes DataType[]
---@return Module
function Module.new(name, location, imports, aliases, infixFns, definitions, dataTypes)
    return setmetatable({
        kind = "Module",
        name = name,
        location = location,
        packageName = nil,
        referencedPackages = {},
        imports = imports or {},
        aliases = aliases or {},
        infixFns = infixFns or {},
        definitions = definitions or {},
        dataTypes = dataTypes or {},
    }, Module)
end

---@param packageName PackageIdentifier
function Module:setPackageName(packageName)
    self.packageName = packageName
end

---@param packages PackageIdentifier[]
function Module:setReferencedPackages(packages)
    self.referencedPackages = packages or {}
end

---@param f fun(stmt: Statement)
function Module:iterate(f)
    f(self)
    for _, imp in ipairs(self.imports) do
        imp:iterate(f)
    end
    for _, a in ipairs(self.aliases) do
        a:iterate(f)
    end
    for _, i in ipairs(self.infixFns) do
        i:iterate(f)
    end
    for _, d in ipairs(self.definitions) do
        d:iterate(f)
    end
    for _, dt in ipairs(self.dataTypes) do
        dt:iterate(f)
    end
end

---@return nil
---@return string
function Module:generate()
    return nil, "TODO: generate"
end

---@return nil
---@return string
function Module:normalize()
    return nil, "TODO: normalize"
end

return { Module = Module }
