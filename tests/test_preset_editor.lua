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
equal(true, Editor:setCustomization(
    added, "Added", 0xAABBCCDD, false, true),
    "working copy can customize an added tile")
equal("Added", Editor:getLabel(added), "customized label stays in the working copy")
equal(0xAABBCCDD, Editor:getColour(added), "customized colour stays in the working copy")
equal(false, Editor:getFill(added), "customized fill stays in the working copy")
equal(true, Editor:getOutlineCornersOnly(added), "customized corners stay in the working copy")
equal(1, #preset.tiles, "editing does not mutate the saved preset")
equal(3200, preset.tiles[1].x, "saved preset keeps its original tile")

local target = { name = "instanced target" }
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

print("test_preset_editor: ok")
