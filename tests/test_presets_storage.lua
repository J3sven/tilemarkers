package.path = "./?.lua;" .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local saved
local saveSucceeds = true
-- Model a bounded structured-data table, rather than an unlimited Lua table.
-- Large tile collections must not depend on native table-entry capacity.
local function storedCopy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    local count = 0
    for key, child in pairs(value) do
        count = count + 1
        assert(count <= 127, "structured-data table capacity exceeded")
        result[key] = storedCopy(child)
    end
    return result
end
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
        if saveSucceeds then saved = storedCopy(value) end
        return saveSucceeds
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
local function reload()
    package.loaded["src/presets"] = nil
    return require("src/presets")
end
PersistentDB.GetStructuredData = function() return storedCopy(saved) end
Presets = reload()
local migratedTile = Presets:get("preset_1").tiles[1]
for key, value in pairs(tile) do
    equal(value, migratedTile[key], "migration preserves " .. key)
end
equal("Styled", Presets:get("preset_1").name, "migration preserves preset name")
equal(true, Presets:isActive("preset_1"), "migration preserves activation")
equal(2, Presets.data.nextId, "migration preserves next ID")

local revisionBeforeEdit = Presets.revision
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
assert(Presets.revision > revisionBeforeEdit, "editing preset tiles invalidates render queries")
local sourceCoord = { level = 1, x = 3300, z = 3301 }
equal(
    "preset_1",
    Presets:findActiveAt(sourceCoord).id,
    "active preset is found by canonical tile coordinate")
equal(
    nil,
    Presets:findActiveAt({ level = 0, x = 3300, z = 3301 }),
    "preset lookup requires the same floor")
Presets.data.presets[#Presets.data.presets + 1] = {
    id = "preset_2",
    name = "Overlapping",
    tiles = { sourceCoord },
}
equal(
    "preset_1",
    Presets:findActiveAt(sourceCoord).id,
    "inactive overlapping preset is ignored")
Presets.data.activeIds[#Presets.data.activeIds + 1] = "preset_2"
equal(
    "preset_2",
    Presets:findActiveAt(sourceCoord).id,
    "later active preset matches rendering precedence")
equal("Edited", reload():get("preset_1").tiles[1].label, "edited label survives reload")

local revisionBeforeRollback = Presets.revision
saveSucceeds = false
equal(false, Presets:updateTiles("preset_1", {
    { x = 3500, z = 3501, level = 1, label = "Unsaved" },
}), "failed preset edit is reported")
equal(3300, Presets:get("preset_1").tiles[1].x, "failed edit restores rendered tiles")
equal("Edited", Presets:get("preset_1").tiles[1].label, "failed edit restores rendered labels")
assert(Presets.revision > revisionBeforeRollback, "failed edit invalidates cached preset tiles")
saveSucceeds = true

local mixedStyles = {
    {},
    { fill = false },
    { fill = true },
    { outlineCornersOnly = false },
    { outlineCornersOnly = true },
    { fill = false, outlineCornersOnly = false },
    { fill = false, outlineCornersOnly = true },
    { fill = true, outlineCornersOnly = false },
    { fill = true, outlineCornersOnly = true },
}
for index, style in ipairs(mixedStyles) do
    style.x = 3400 + index
    style.z = 3400
    style.level = 0
end

local function assertMixedStyles(preset, context)
    equal(#mixedStyles, #preset.tiles, context .. " tile count")
    for index, expected in ipairs(mixedStyles) do
        local actual = preset.tiles[index]
        equal(expected.x, actual.x, context .. " tile coordinate")
        equal(expected.fill, actual.fill, context .. " fill " .. index)
        equal(expected.outlineCornersOnly, actual.outlineCornersOnly, context .. " corners " .. index)
    end
end

equal(true, Presets:updateTiles("preset_1", mixedStyles), "mixed overrides save")
local exported, token = Presets:export("preset_1")
assert(exported, token)

package.loaded["src/presets"] = nil
Presets = require("src/presets")
assertMixedStyles(Presets:get("preset_1"), "reloaded preset")

local imported, importedPreset = Presets:import(token)
assert(imported, importedPreset)
assertMixedStyles(importedPreset, "imported preset")
local importedId = importedPreset.id
package.loaded["src/presets"] = nil
Presets = require("src/presets")
assertMixedStyles(Presets:get(importedId), "reloaded imported preset")

local created, emptyPreset = Presets:create("  Empty route  ", {}, true)
assert(created, emptyPreset)
equal("Empty route", emptyPreset.name, "empty preset keeps its trimmed name")
equal(nil, next(emptyPreset.tiles), "new preset has no tiles")
local emptyID = emptyPreset.id
package.loaded["src/presets"] = nil
Presets = require("src/presets")
equal("Empty route", Presets:get(emptyID).name, "empty preset survives storage reload")
equal(nil, next(Presets:get(emptyID).tiles), "reload does not populate an empty preset")
equal(true, Presets:isActive(emptyID), "empty preset activation survives reload")
local emptyExported, emptyToken = Presets:export(emptyID)
assert(emptyExported, emptyToken)
local emptyImported, importedEmpty = Presets:import(emptyToken)
assert(emptyImported, importedEmpty)
equal("Empty route", importedEmpty.name, "empty export preserves preset name")
equal(nil, next(importedEmpty.tiles), "empty preset round-trips through sharing")

local Editor = require("src/preset_editor")
equal(true, Editor:begin(Presets:get(emptyID)), "empty preset can enter edit mode")
equal(true, Presets:updateTiles(emptyID, Editor:export()), "empty edit can be saved")
equal(true, Editor:add(sourceCoord, { text = "First tile" }), "first tile can be added")
equal(true, Presets:updateTiles(emptyID, Editor:export()), "first tile can be saved")
equal("First tile", Presets:get(emptyID).tiles[1].label, "saved preset contains its first tile")
equal(true, Editor:remove(sourceCoord), "last tile can be removed")
equal(true, Presets:updateTiles(emptyID, Editor:export()), "preset can be saved empty again")
Editor:cancel()
package.loaded["src/presets"] = nil
Presets = require("src/presets")
equal(nil, next(Presets:get(emptyID).tiles), "emptied preset survives another reload")

local previousNextID = Presets.data.nextId
saveSucceeds = false
equal(false, Presets:create("Unsaved empty", {}, true), "failed empty creation is reported")
equal(previousNextID, Presets.data.nextId, "failed empty creation restores the ID sequence")
equal(nil, Presets:get("preset_" .. tostring(previousNextID)), "failed empty creation leaves no preset")
equal(false, Presets:isActive("preset_" .. tostring(previousNextID)), "failed empty creation leaves no activation")
saveSucceeds = true

local largePresets = {}
for presetIndex = 1, 3 do
    local tiles = {}
    for index = 1, 2000 do
        tiles[index] = {
            x = 3200 + (index - 1) // 64,
            z = 3200 + (index - 1) % 64,
            level = presetIndex - 1,
            label = index % 5 == 0 and "Route " .. (index % 3) or nil,
            outlineColour = 0x12345678,
            fillColour = 0xABCDEF12,
            outlineCornersOnly = index % 2 == 0,
            outlineThickness = 6.5,
        }
        if index % 3 ~= 2 then tiles[index].fill = index % 3 == 0 end
    end
    local success, preset = Presets:create("Large route " .. presetIndex, tiles, true)
    assert(success, preset)
    largePresets[#largePresets + 1] = preset
end

local function assertPreset(expected, actual, context)
    equal(expected.name, actual.name, context .. " name")
    equal(#expected.tiles, #actual.tiles, context .. " tile count")
    for index, expectedTile in ipairs(expected.tiles) do
        for _, field in ipairs({
            "x", "z", "level", "label", "outlineColour", "fillColour",
            "fill", "outlineCornersOnly", "outlineThickness",
        }) do
            equal(expectedTile[field], actual.tiles[index][field],
                context .. " tile " .. index .. " " .. field)
        end
    end
end

Presets = reload()
for _, expected in ipairs(largePresets) do
    assertPreset(expected, Presets:get(expected.id), "large storage reload")
    equal(true, Presets:isActive(expected.id), "large preset stays active")
    local success, shareToken = Presets:export(expected.id)
    assert(success, shareToken)
    assert(#shareToken <= 9999, "large route fits the native sharing field")
    local success, imported = Presets:import(shareToken)
    assert(success, imported)
    assertPreset(expected, imported, "large import")
    assertPreset(expected, reload():get(imported.id), "large import reload")
end

local editedLarge = largePresets[1]
table.remove(editedLarge.tiles, 128)
editedLarge.tiles[128].label = "Edited beyond old limit"
equal(true, Presets:updateTiles(editedLarge.id, editedLarge.tiles), "large edit saves")
assertPreset(editedLarge, reload():get(editedLarge.id), "large edit reload")

print("test_presets_storage: ok")
