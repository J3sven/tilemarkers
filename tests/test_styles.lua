package.path = "./?.lua;" .. package.path

local Styles = require("src/styles")

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local defaults = Styles.normalize()
equal(0xC864FFFF, defaults.outlineColour, "default outline")
equal(0xA050CC8C, defaults.fillColour, "default fill is darker and more transparent")
equal(true, defaults.fill, "default fill enabled")
equal(false, defaults.outlineCornersOnly, "default outline remains continuous")
equal(2.0, defaults.outlineThickness, "default thickness")

local custom = Styles.normalize({
    outlineColour = 0x12345678,
    fillColour = 0xABCDEF42,
    fill = false,
    outlineThickness = 7.5,
})
equal(0x12345678, custom.outlineColour, "custom outline")
equal(0xABCDEF42, custom.fillColour, "custom fill")
equal(false, custom.fill, "custom fill disabled")
equal(7.5, custom.outlineThickness, "custom thickness")

local inheritedFill = Styles.normalize({ outlineColour = 0x01020320 })
equal(0x01020212, inheritedFill.fillColour, "fill derives from outline colour and alpha")

local derived = Styles.fromColour(0x12345678, false, true)
equal(0x12345678, derived.outlineColour, "chosen colour becomes exact outline")
equal(0x0E2A4542, derived.fillColour, "chosen colour derives darker translucent fill")
equal(false, derived.fill, "derived style preserves fill toggle")
equal(true, derived.outlineCornersOnly, "derived style preserves corner-only outline")

local legacy = Styles.normalize({ colorIndex = 1 })
equal(0x00FFFFFF, legacy.outlineColour, "legacy palette outline migration")
equal(0x00FFFF8C, legacy.fillColour, "legacy palette fill migration")

local clamped = Styles.normalize({ outlineThickness = 99 })
equal(10.0, clamped.outlineThickness, "thickness upper clamp")

local exactHex = Styles.normalize({
    outlineColour = "B3489EFF",
    fillColour = "395E2D2E",
})
equal(0xB3489EFF, exactHex.outlineColour, "hex outline storage is exact")
equal(0x395E2D2E, exactHex.fillColour, "hex fill storage is exact")
equal("B3489EFF", Styles.encodeColour(exactHex.outlineColour), "colour encoding")
equal(
    0xB3489E00,
    Styles.normalize({ outlineColour = "B3489E00" }).outlineColour,
    "explicit transparent hex remains transparent")

local roundedStructuredColours = Styles.normalize({
    outlineColour = 3007880960.0,
    fillColour = 962473216.0,
})
equal(0xB3489FFF, roundedStructuredColours.outlineColour, "rounded outline alpha recovery")
equal(0x395E2D8C, roundedStructuredColours.fillColour, "rounded fill alpha recovery")

print("test_styles: ok")
