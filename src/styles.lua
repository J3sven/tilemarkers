local Colours = require("src/colours")

local Styles = {}

local DEFAULT_OUTLINE = Colours.rgba(Colours.DEFAULT_INDEX, 0xFF)
local DEFAULT_THICKNESS = 2.0
local FILL_DARKEN_NUMERATOR = 4
local FILL_DARKEN_DENOMINATOR = 5
local FILL_ALPHA = 0x8C

local function derivedFillColour(outlineColour)
    local function darken(channel)
        return (channel * FILL_DARKEN_NUMERATOR
            + FILL_DARKEN_DENOMINATOR // 2)
            // FILL_DARKEN_DENOMINATOR
    end

    local red = darken((outlineColour >> 24) & 0xFF)
    local green = darken((outlineColour >> 16) & 0xFF)
    local blue = darken((outlineColour >> 8) & 0xFF)
    local alpha = ((outlineColour & 0xFF) * FILL_ALPHA + 0x7F) // 0xFF
    return (red << 24) | (green << 16) | (blue << 8) | alpha
end

local DEFAULT_FILL = derivedFillColour(DEFAULT_OUTLINE)

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function colourNumber(value)
    if type(value) == "string" then
        local hexadecimal = value:match("^#?(%x%x%x%x%x%x%x%x)$")
            or value:match("^0[xX](%x%x%x%x%x%x%x%x)$")
        if hexadecimal ~= nil then
            return tonumber(hexadecimal, 16), false
        end
    end

    local number = tonumber(value)
    return number, type(value) == "number" and math.type(value) == "float"
end

local function rgba(value, fallback, recoveredAlpha)
    local wasStructuredFloat
    value, wasStructuredFloat = colourNumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return fallback
    end
    local result = math.floor(value) & 0xFFFFFFFF
    -- StructuredDB historically serialized RGBA integers as floats. At the
    -- upper end of the 32-bit range that rounds away the entire alpha byte.
    -- Hexadecimal strings are exact, so only repair legacy numeric floats.
    if wasStructuredFloat
        and result > 0xFFFFFF
        and (result & 0xFF) == 0 then
        result = (result & 0xFFFFFF00) | recoveredAlpha
    end
    return result
end

local function legacyStyle(metadata)
    if metadata == nil or metadata.colorIndex == nil then return nil end
    local index = Colours.normalize(metadata.colorIndex)
    return {
        outlineColour = Colours.rgba(index, 0xFF),
        fillColour = Colours.rgba(index, 0x8C),
    }
end

local function booleanOrDefault(value, fallback)
    if value == nil then return fallback end
    return value == true
end

function Styles.normalize(metadata, defaults)
    metadata = type(metadata) == "table" and metadata or {}
    local legacy = legacyStyle(metadata)
    local outlineColour = rgba(
        metadata.outlineColour,
        legacy and legacy.outlineColour or DEFAULT_OUTLINE,
        0xFF)
    local defaultFill = derivedFillColour(outlineColour)

    return {
        outlineColour = outlineColour,
        fillColour = rgba(
            metadata.fillColour,
            legacy and legacy.fillColour or defaultFill,
            FILL_ALPHA),
        fill = booleanOrDefault(metadata.fill, defaults and defaults.fill),
        outlineCornersOnly = booleanOrDefault(
            metadata.outlineCornersOnly, defaults and defaults.outlineCornersOnly),
        outlineThickness = clamp(
            tonumber(metadata.outlineThickness) or DEFAULT_THICKNESS,
            0.0,
            10.0),
    }
end

function Styles.fromColour(colour, fill, outlineCornersOnly)
    local outlineColour = rgba(colour, DEFAULT_OUTLINE, 0xFF)
    return {
        outlineColour = outlineColour,
        fillColour = derivedFillColour(outlineColour),
        fill = booleanOrDefault(fill),
        outlineCornersOnly = booleanOrDefault(outlineCornersOnly),
        outlineThickness = DEFAULT_THICKNESS,
    }
end

function Styles.encodeColour(colour)
    return string.format("%08X", rgba(colour, 0xFFFFFFFF, 0xFF))
end

function Styles.copy(style)
    local normalized = Styles.normalize(style)
    return {
        outlineColour = normalized.outlineColour,
        fillColour = normalized.fillColour,
        fill = normalized.fill,
        outlineCornersOnly = normalized.outlineCornersOnly,
        outlineThickness = normalized.outlineThickness,
    }
end

Styles.DEFAULT_OUTLINE = DEFAULT_OUTLINE
Styles.DEFAULT_FILL = DEFAULT_FILL
Styles.DEFAULT_THICKNESS = DEFAULT_THICKNESS

return Styles
