package.path = "./?.lua;" .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

CoordGrid = {
    new = function(level, mapX, mapZ, localX, localZ)
        return {
            level = level,
            x = mapX * 64 + localX,
            z = mapZ * 64 + localZ,
        }
    end,
}

package.loaded["src/preset_editor"] = nil
local Editor = require("src/preset_editor")
local preset = {
    id = "preset_7",
    name = "Editable route",
    tiles = {
        {
            x = 3200,
            z = 3201,
            level = 0,
            label = "Start",
            outlineColour = 0x112233FF,
            fill = false,
        },
    },
}
local existing = { level = 0, x = 3200, z = 3201 }
local added = { level = 0, x = 3202, z = 3203 }

equal(true, Editor:begin(preset), "editor starts from a preset")
equal(true, Editor:isActive(), "editor reports its active session")
equal(true, Editor:contains(existing), "working copy contains the original tile")
equal("Start", Editor:getLabel(existing), "working copy retains the original label")
equal(true, Editor:remove(existing), "working copy can remove a preset tile")
equal(false, Editor:contains(existing), "removed tile leaves the working copy")
equal(true, Editor:add(added, {
    outlineColour = 0x445566FF,
    fill = true,
}), "working copy can add a tile")
local target = { name = "instanced target" }
equal(true, Editor:previewCustomization(
    added, "Preview", 0x010203FF, false, true),
    "working copy accepts a transient customization preview")
equal("Preview", Editor:getLabel(added), "preview label is exposed immediately")
equal(0x010203FF, Editor:getColour(added), "preview colour is exposed immediately")
local previewQuery = Editor:query(existing, 30, {
    { source = added, target = target },
})
equal("Preview", previewQuery[target].text, "preview reaches working-copy tile queries")
equal(nil, Editor:export()[1].label, "preview is not committed to preset export")
equal(
    true,
    Editor:cancelCustomizationPreview(added),
    "working-copy preview can be cancelled")
equal(nil, Editor:getLabel(added), "cancel restores the pre-edit label")
equal(0x445566FF, Editor:getColour(added), "cancel restores the pre-edit colour")
equal(true, Editor:getFill(added), "cancel restores the pre-edit fill")
equal(true, Editor:setCustomization(
    added, "Added", 0xAABBCCDD, false, true),
    "working copy can customize an added tile")
equal("Added", Editor:getLabel(added), "customized label stays in the working copy")
equal(0xAABBCCDD, Editor:getColour(added), "customized colour stays in the working copy")
equal(false, Editor:getFill(added), "customized fill stays in the working copy")
equal(true, Editor:getOutlineCornersOnly(added), "customized corners stay in the working copy")
equal(1, #preset.tiles, "editing does not mutate the saved preset")
equal(3200, preset.tiles[1].x, "saved preset keeps its original tile")

local queried = Editor:query(existing, 30, {
    { source = added, target = target },
})
equal("Added", queried[target].text, "working copy maps through region bindings")
local exported = Editor:export()
equal(1, #exported, "export contains the edited tile set")
equal(3202, exported[1].x, "export contains the added tile")

Editor:cancel()
equal(false, Editor:isActive(), "cancel exits edit mode")
equal(1, #preset.tiles, "cancel leaves saved tiles untouched")

equal(true, Editor:begin(preset), "editor can reopen the saved preset")
equal(false, Editor:getFill(existing), "opening preserves an explicit disabled fill")
equal(nil, Editor:getOutlineCornersOnly(existing), "opening preserves inherited corners")
Editor:add(added, { outlineColour = 0x445566FF })
equal(nil, Editor:getFill(added), "new editor tile inherits fill")
equal(nil, Editor:getOutlineCornersOnly(added), "new editor tile inherits corners")
Editor:previewCustomization(added, "", 0x445566FF, false, true)
equal(false, Editor:getFill(added), "editor preview can disable inherited fill")
equal(true, Editor:getOutlineCornersOnly(added), "editor preview can override inherited corners")
Editor:cancelCustomizationPreview(added)
equal(nil, Editor:getFill(added), "editor cancel restores inherited fill")
equal(nil, Editor:getOutlineCornersOnly(added), "editor cancel restores inherited corners")

Editor:setCustomization(added, "", 0x445566FF, true, false)
Editor:previewCustomization(added, "", 0x445566FF, nil, nil)
previewQuery = Editor:query(existing, 30, { { source = added, target = target } })
equal(nil, previewQuery[target].fill, "editor query renders fill reset preview")
equal(nil, previewQuery[target].outlineCornersOnly, "editor query renders corner reset preview")
exported = Editor:export()
equal(true, exported[2].fill, "reset preview does not commit fill to export")
equal(false, exported[2].outlineCornersOnly, "reset preview does not commit corners to export")
Editor:cancelCustomizationPreview(added)
equal(true, Editor:getFill(added), "editor cancelled reset restores true fill")
equal(false, Editor:getOutlineCornersOnly(added), "editor cancelled reset restores false corners")

Editor:previewCustomization(added, "", 0x445566FF, nil, false)
Editor:setCustomization(added, "", 0x445566FF, nil, false)
Editor:setCustomization(existing, "Start", 0x112233FF, false, true)
Editor:setCustomization(existing, "Start", 0x112233FF, false, nil)
local editedPreset = { id = preset.id, name = preset.name, tiles = Editor:export() }
Editor:cancel()
Editor:begin(editedPreset)
equal(nil, Editor:getFill(added), "fill reset survives export and reopening")
equal(false, Editor:getOutlineCornersOnly(added), "false corner override survives export and reopening")
equal(false, Editor:getFill(existing), "false fill override survives export and reopening")
equal(nil, Editor:getOutlineCornersOnly(existing), "corner reset survives export and reopening")
equal(false, preset.tiles[1].fill, "editing keeps the original preset fill untouched")
equal(nil, preset.tiles[1].outlineCornersOnly, "editing keeps original inheritance untouched")
Editor:cancel()

print("test_preset_editor: ok")
