---Integer kind tags for runtime objects (runtime-2, optimized).
---
---Unlike runtime/object_kind.lua (string tags), runtime-2 uses small
---integers so dispatch is a single integer compare. Type identity at
---the object level is provided by per-kind metatables in object.lua;
---these integer codes are returned by Object.getKind() for callers
---that need to switch on kind explicitly.
---
---The numeric assignments do not need to match any external enum: the
---only externally visible names are UNIT_NAME_TRUE / UNIT_NAME_FALSE,
---which mirror runtime.h.

local ObjectKind             = {
    UNKNOWN  = 0,
    UNIT     = 1,
    CHAR     = 2,
    INT      = 3,
    FLOAT    = 4,
    STRING   = 5,
    RECORD   = 6,
    TUPLE    = 7,
    LIST     = 8,
    OPTION   = 9,
    FUNCTION = 10,
    CLOSURE  = 11,
    NATIVE   = 12,
    PATTERN  = 13,
}

ObjectKind.OPTION_NAME_TRUE  = "Nar.Base.Basics.Bool#True"
ObjectKind.OPTION_NAME_FALSE = "Nar.Base.Basics.Bool#False"

---Human-readable name (kept for error messages).
---@param k integer
---@return string
function ObjectKind.name(k)
    if k == ObjectKind.UNIT then return "unit" end
    if k == ObjectKind.CHAR then return "char" end
    if k == ObjectKind.INT then return "int" end
    if k == ObjectKind.FLOAT then return "float" end
    if k == ObjectKind.STRING then return "string" end
    if k == ObjectKind.RECORD then return "record" end
    if k == ObjectKind.TUPLE then return "tuple" end
    if k == ObjectKind.LIST then return "list" end
    if k == ObjectKind.OPTION then return "option" end
    if k == ObjectKind.FUNCTION then return "function" end
    if k == ObjectKind.CLOSURE then return "closure" end
    if k == ObjectKind.NATIVE then return "native" end
    if k == ObjectKind.PATTERN then return "pattern" end
    return "unknown"
end

return ObjectKind
