package.path = "./?.lua;" .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local saved
local saveSucceeds = true
local saveCount = 0
PersistentDB = {
    GetStructuredData = function()
        return {
            [0] = {
                [258] = {
                    [12345] = {
                        text = "Legacy",
                        outlineColour = 3007880960.0,
                        fillColour = 962473216.0,
                        fill = true,
                        outlineThickness = 4.0,
                    },
                },
            },
        }
    end,
    SetStructuredData = function(_, _, value)
        saveCount = saveCount + 1
        if saveSucceeds then saved = value end
        return saveSucceeds
    end,
}

package.loaded["src/tiles"] = nil
local Tiles = require("src/tiles")

equal(2, saved.version, "legacy storage is migrated")
equal("B3489FFF", saved.levels[0][258][12345].outlineColour, "outline migrated to hex")
equal("395E2D8C", saved.levels[0][258][12345].fillColour, "fill migrated to hex")

local source = {
    level = 0,
    mapSquareX = 1,
    mapSquareZ = 2,
    ToPacked = function() return 12345 end,
}
local target = {}
local queried = Tiles:query(source, 0, {
    { source = source, target = target },
})
equal(0xB3489FFF, queried[target].outlineColour, "migrated outline remains available")
equal(true, Tiles:contains(source), "stored marker is detected")
equal(0x395E2D8C, queried[target].fillColour, "migrated fill remains available")

local added = {
    level = 0,
    mapSquareX = 1,
    mapSquareZ = 2,
    ToPacked = function() return 54321 end,
}
equal(false, Tiles:contains(added), "unmarked tile is not detected")
Tiles:add(added, {
    outlineColour = 0x12345678,
    fillColour = 0xABCDEF42,
    fill = false,
    outlineThickness = 7.5,
})
equal("12345678", saved.levels[0][258][54321].outlineColour, "new outline saves exactly")
equal("ABCDEF42", saved.levels[0][258][54321].fillColour, "new fill saves exactly")
equal(false, saved.levels[0][258][54321].fill, "fill setting persists")
equal(7.5, saved.levels[0][258][54321].outlineThickness, "thickness persists")
equal(true, Tiles:contains(added), "new marker is detected")
equal(nil, Tiles:getLabel(added), "unlabelled marker has no label")
equal(true, Tiles:setLabel(added, "Safe tile"), "an existing tile accepts a label")
equal("Safe tile", Tiles:getLabel(added), "existing label is exposed")
equal("Safe tile", saved.levels[0][258][54321].text, "tile label persists")
equal(true, Tiles:setLabel(added, ""), "empty label clears an existing label")
equal(nil, Tiles:getLabel(added), "cleared marker has no label")
equal(nil, saved.levels[0][258][54321].text, "cleared label is removed from storage")
equal(true, Tiles:setLabel(added, "Safe tile"), "label can be restored")
equal(0x12345678, Tiles:getColour(added), "stored outline is exposed as tile colour")
equal(false, Tiles:getFill(added), "stored fill state is exposed")
equal(false, Tiles:getOutlineCornersOnly(added), "stored outline defaults continuous")
equal(
    true,
    Tiles:setColour(added, 0x12345678, true, true),
    "existing tile accepts colour, fill, and corner outline")
equal("12345678", saved.levels[0][258][54321].outlineColour, "recolour stores exact outline")
equal("0E2A4542", saved.levels[0][258][54321].fillColour, "recolour stores derived fill")
equal(true, saved.levels[0][258][54321].fill, "recolour stores selected fill state")
equal(true, saved.levels[0][258][54321].outlineCornersOnly, "corner outline persists")
local savesBeforeCustomization = saveCount
equal(
    true,
    Tiles:setCustomization(added, "Combined", 0xAABBCCDD, false, false),
    "existing tile accepts combined label and style customization")
equal(saveCount, savesBeforeCustomization + 1, "combined customization performs one save")
equal("Combined", Tiles:getLabel(added), "combined customization updates the label")
equal(0xAABBCCDD, Tiles:getColour(added), "combined customization updates the colour")
equal(false, Tiles:getFill(added), "combined customization updates the fill state")
equal(false, Tiles:getOutlineCornersOnly(added), "combined customization updates outline corners")
equal(
    true,
    Tiles:setCustomization(added, "", 0x12345678, true, true),
    "empty combined label is accepted as a clear")
equal(nil, Tiles:getLabel(added), "empty combined label clears the stored label")
equal(true, Tiles:setLabel(added, "Safe tile"), "label can be restored after customization")
equal(false, Tiles:setLabel({
    level = 0,
    mapSquareX = 9,
    mapSquareZ = 9,
    ToPacked = function() return 99999 end,
}, "Missing"), "a missing tile is not labelled")

local reloadedStorage = saved
PersistentDB.GetStructuredData = function() return reloadedStorage end
package.loaded["src/tiles"] = nil
Tiles = require("src/tiles")
queried = Tiles:query(added, 0, {
    { source = added, target = target },
})
equal(0x12345678, queried[target].outlineColour, "outline survives reload")
equal(0x0E2A4542, queried[target].fillColour, "derived fill survives reload")
equal(true, queried[target].fill, "changed fill state survives reload")
equal(true, queried[target].outlineCornersOnly, "corner outline survives reload")
equal(7.5, queried[target].outlineThickness, "thickness survives reload")
equal("Safe tile", queried[target].text, "label survives reload")

local visibleExport = Tiles:exportCoords({ added, added })
equal(1, #visibleExport, "coordinate export deduplicates visible markers")
equal(added.level, visibleExport[1].level, "coordinate export keeps visible level")
equal(0x12345678, visibleExport[1].outlineColour, "coordinate export keeps marker style")

local removed, removedCount = Tiles:removeAll({ added })
equal(true, removed, "visible tile batch is saved")
equal(1, removedCount, "visible tile batch reports its removed marker count")
equal(nil, Tiles:query(added, 0, {
    { source = added, target = target },
})[target], "batch-removed tile is no longer available")
equal(false, Tiles:contains(added), "removed marker is no longer detected")

saveSucceeds = false
removed, removedCount = Tiles:removeAll({ source })
equal(false, removed, "failed batch save is reported")
equal(0, removedCount, "failed batch save reports no committed removals")
equal(true, Tiles:query(source, 0, {
    { source = source, target = target },
})[target] ~= nil, "failed batch save restores removed markers")

print("test_tiles: ok")
