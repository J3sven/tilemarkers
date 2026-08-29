package.path = "./?.lua;" .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local saved
PersistentDB = {
    GetStructuredData = function()
        return {
            version = 2,
            nextId = 2,
            activeIds = { "preset_1" },
            presets = {
                {
                    id = "preset_1",
                    name = "Styled",
                    tiles = {
                        {
                            x = 3200,
                            z = 3201,
                            level = 0,
                            outlineColour = 3007880960.0,
                            fillColour = 962473216.0,
                            fill = false,
                            outlineCornersOnly = true,
                            outlineThickness = 6.5,
                        },
                    },
                },
            },
        }
    end,
    SetStructuredData = function(_, _, value)
        saved = value
        return true
    end,
}

package.loaded["src/presets"] = nil
local Presets = require("src/presets")
local tile = Presets.data.presets[1].tiles[1]

equal(0xB3489FFF, tile.outlineColour, "preset outline alpha is recovered")
equal(0x395E2D8C, tile.fillColour, "preset fill alpha is recovered")
equal(false, tile.fill, "preset fill toggle is retained")
equal(true, tile.outlineCornersOnly, "preset corner outline is retained")
equal(6.5, tile.outlineThickness, "preset thickness is retained")
equal("hex", saved.colourEncoding, "preset colour encoding is versioned")
equal("B3489FFF", saved.presets[1].tiles[1].outlineColour, "preset outline saves as hex")
equal("395E2D8C", saved.presets[1].tiles[1].fillColour, "preset fill saves as hex")
equal(true, saved.presets[1].tiles[1].outlineCornersOnly, "preset corner outline saves")

equal(true, Presets:updateTiles("preset_1", {
    {
        x = 3300,
        z = 3301,
        level = 1,
        label = "Edited",
        outlineColour = 0x123456FF,
        fill = true,
    },
}), "preset edit replaces its tiles")
equal(3300, Presets:get("preset_1").tiles[1].x, "edited tile reaches live preset data")
equal("Edited", saved.presets[1].tiles[1].label, "edited label reaches storage")
local emptySuccess, emptyMessage = Presets:updateTiles("preset_1", {})
equal(false, emptySuccess, "preset edit rejects an empty tile set")
equal(
    "A preset must contain at least one tile.",
    emptyMessage,
    "empty preset edit explains why save remains open")
equal(3300, Presets:get("preset_1").tiles[1].x, "rejected edit preserves saved tiles")

print("test_presets_storage: ok")
