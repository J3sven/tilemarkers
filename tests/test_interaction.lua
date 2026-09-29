package.path = "./?.lua;" .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local callbacks = {}
local function event(name)
    return {
        Subscribe = function(id, callback)
            equal("tileMarker", id, name .. " subscription ID")
            callbacks[name] = callback
        end,
        Unsubscribe = function() end,
    }
end

Event = {
    Draw = event("Draw"),
    MiniMenuReady = event("MiniMenuReady"),
    MiniMenuClosed = event("MiniMenuClosed"),
    GameStateChanged = event("GameStateChanged"),
}

local hover = { name = "target" }
local cursorHover = hover
local mousePosition = { x = 100, y = 100 }
local source = { name = "source" }
local playerCoord = { name = "player" }
local controlDown = false
local shiftDown = false
local keyboardBlocked = false

Keyboard = {
    IsAvailable = function() return true end,
    IsBlocked = function() return keyboardBlocked end,
    IsControlDown = function() return controlDown end,
    IsShiftDown = function() return shiftDown end,
}
Mouse = {
    IsAvailable = function() return true end,
    GetPosition = function() return mousePosition end,
}
ScreenConvert = {
    ScreenToCoordGrid = function() return cursorHover end,
}
Player = {
    IsAvailable = function() return true end,
    GetEntity = function()
        return { isValid = true, coordGrid = playerCoord }
    end,
}
MiniMenuActionType = {
    WALK = 23,
    CANCEL = 1006,
    OP_LOC1 = 3,
    OP_LOC2 = 4,
}
GameState = { GAME = 1 }
local miniMenuOpen = false
MiniMenu = {
    IsOpen = function() return miniMenuOpen end,
}

local marked = false
local existingLabel = "Existing label"
local existingColour = 0x12345678
local recolouredSource
local recolouredValue
local addedSource
local removedSource
local addedMetadata
local labelledSource
local labelledText
local existingFill = false
local recolouredFill
local existingOutlineCornersOnly = false
local recolouredOutlineCornersOnly
local previewedSource
local previewedLabel
local previewedColour
local previewedFill
local previewedOutlineCornersOnly
local cancelledPreviewSource
local queriedTiles = {}
local queriedCoord
local queriedDistance
local clearedSources
local exportedCoords
local visibleExportTiles = {
    { x = 3200, z = 3201, level = 0 },
}
local allExportTiles = {
    { x = 3000, z = 3001, level = 0 },
}
local tilesCleared = false
local Tiles = {
    query = function(_, coord, distance)
        queriedCoord = coord
        queriedDistance = distance
        return queriedTiles
    end,
    contains = function(_, coord)
        equal(source, coord, "mark state uses canonical source coordinate")
        return marked
    end,
    add = function(_, coord, metadata)
        marked = true
        addedSource = coord
        addedMetadata = metadata
    end,
    remove = function(_, coord)
        marked = false
        removedSource = coord
    end,
    getLabel = function(_, coord)
        equal(source, coord, "existing label uses canonical source coordinate")
        return existingLabel
    end,
    setLabel = function(_, coord, text)
        labelledSource = coord
        labelledText = text
        existingLabel = text ~= "" and text or nil
    end,
    getColour = function(_, coord)
        equal(source, coord, "existing colour uses canonical source coordinate")
        return existingColour
    end,
    getFill = function(_, coord)
        equal(source, coord, "existing fill uses canonical source coordinate")
        return existingFill
    end,
    getOutlineCornersOnly = function(_, coord)
        equal(source, coord, "existing corner outline uses canonical source coordinate")
        return existingOutlineCornersOnly
    end,
    setColour = function(_, coord, colour, fill, outlineCornersOnly)
        recolouredSource = coord
        recolouredValue = colour
        recolouredFill = fill
        recolouredOutlineCornersOnly = outlineCornersOnly
        existingColour = colour
        existingFill = fill
        existingOutlineCornersOnly = outlineCornersOnly
    end,
    previewCustomization = function(_, coord, label, colour, fill, outlineCornersOnly)
        previewedSource = coord
        previewedLabel = label
        previewedColour = colour
        previewedFill = fill
        previewedOutlineCornersOnly = outlineCornersOnly
    end,
    cancelCustomizationPreview = function(_, coord)
        cancelledPreviewSource = coord
        previewedSource = nil
        previewedLabel = nil
        previewedColour = nil
        previewedFill = nil
        previewedOutlineCornersOnly = nil
    end,
    setCustomization = function(_, coord, label, colour, fill, outlineCornersOnly)
        labelledSource = coord
        labelledText = label
        existingLabel = label ~= "" and label or nil
        recolouredSource = coord
        recolouredValue = colour
        recolouredFill = fill
        recolouredOutlineCornersOnly = outlineCornersOnly
        existingColour = colour
        existingFill = fill
        existingOutlineCornersOnly = outlineCornersOnly
    end,
    removeAll = function(_, coords)
        clearedSources = coords
        return true, #coords
    end,
    export = function()
        return allExportTiles
    end,
    exportCoords = function(_, coords)
        exportedCoords = coords
        return visibleExportTiles
    end,
    clear = function()
        tilesCleared = true
        return true
    end,
}

local createdPresetName
local createdPresetTiles
local deletedPresetID
local excludedPresetID
local updatedPresetID
local updatedPresetTiles
local presetAtSource
local startedPresetEditID
local startedPresetEditName
local Presets = {
    list = function() return {} end,
    isActive = function() return false end,
    setActive = function() return true end,
    create = function(_, name, tiles)
        createdPresetName = name
        createdPresetTiles = tiles
        return true, { id = "preset_test", name = name }
    end,
    rename = function() return true end,
    delete = function(_, id)
        deletedPresetID = id
        return true
    end,
    export = function() return true, "TM2token" end,
    import = function() return true end,
    query = function(_, _, _, _, excludedID)
        excludedPresetID = excludedID
        return {}
    end,
    findActiveAt = function(_, coord)
        equal(source, coord, "preset lookup uses canonical source coordinate")
        return presetAtSource
    end,
    get = function(_, id)
        return id == "preset_1" and {
            id = id,
            name = "Editable",
            tiles = {},
        } or nil
    end,
    updateTiles = function(_, id, tiles)
        updatedPresetID = id
        updatedPresetTiles = tiles
        return true, "Saved"
    end,
}
local editActive = false
local editMarked = false
local editAddedSource
local editRemovedSource
local PresetEditor = {
    presetID = nil,
    isActive = function() return editActive end,
    begin = function(self, preset)
        editActive = true
        self.presetID = preset.id
        return true
    end,
    cancel = function(self)
        editActive = false
        self.presetID = nil
    end,
    export = function()
        return { { x = 3300, z = 3301, level = 0 } }
    end,
    query = function()
        return { [hover] = { text = "Working copy" } }
    end,
    contains = function() return editMarked end,
    add = function(_, coord)
        editMarked = true
        editAddedSource = coord
    end,
    remove = function(_, coord)
        editMarked = false
        editRemovedSource = coord
    end,
    getLabel = function() return "Preset label" end,
    getColour = function() return 0x102030FF end,
    getFill = function() return true end,
    getOutlineCornersOnly = function() return false end,
    setCustomization = function() end,
    previewCustomization = function() end,
    cancelCustomizationPreview = function() end,
}
local RegionBindings = {
    resolveArea = function() return nil end,
    toSource = function(coord)
        equal(hover, coord, "hover is converted to source coordinate")
        return source
    end,
    clear = function() end,
}

local drawnHover
local drawnTiles
local promptOpen = false
local hoverPreviewEnabled = true
local promptedInitialLabel
local promptedInitialColour
local promptedInitialFill
local promptedInitialOutlineCornersOnly
local rememberedColour
local promptedCustomizationActions
local promptedClearCount
local clearConfirmation
local initializedPresetHandlers
local promptedPresetCreationVisible
local promptedPresetImport = false
local UI = {
    init = function(_, handlers)
        initializedPresetHandlers = handlers
    end,
    ensureMounted = function() return true end,
    draw = function(_, tiles, tile)
        drawnTiles = tiles
        drawnHover = tile
    end,
    getStyle = function()
        return {
            outlineColour = 0x12345678,
            fillColour = 0x0E2A4542,
        }
    end,
    isPromptOpen = function() return promptOpen end,
    isHoverPreviewEnabled = function() return hoverPreviewEnabled end,
    promptForCustomization = function(
        _, initialLabel, initialColour, initialFill, initialOutlineCornersOnly, actions)
        promptedInitialLabel = initialLabel
        promptedInitialColour = initialColour
        promptedInitialFill = initialFill
        promptedInitialOutlineCornersOnly = initialOutlineCornersOnly
        promptedCustomizationActions = actions
    end,
    promptForClear = function(_, tileCount, callback)
        promptedClearCount = tileCount
        clearConfirmation = callback
        return true
    end,
    promptForPresetCreation = function(_, visibleOnly)
        promptedPresetCreationVisible = visibleOnly
        return true
    end,
    promptForPresetImport = function()
        promptedPresetImport = true
        return true
    end,
    startPresetEdit = function(_, id, name)
        startedPresetEditID = id
        startedPresetEditName = name
        return initializedPresetHandlers.startEdit(id)
    end,
    rememberColour = function(_, colour)
        rememberedColour = colour
    end,
    destroySettings = function() end,
    destroyContent = function() end,
    destroy = function() end,
    shutdown = function() end,
}

package.loaded["src/tiles"] = Tiles
package.loaded["src/presets"] = Presets
package.loaded["src/preset_editor"] = PresetEditor
package.loaded["src/region_bindings"] = RegionBindings
package.loaded["src/ui"] = UI
prettyui = {}
log = function() end

dofile("main.lua")

equal(nil, Event.Logic, "legacy hotkey logic event is not required")
equal(nil, Event.MiniMenuEntrySelected, "legacy click interception event is not required")

callbacks.Draw()
equal(nil, drawnHover, "hover is hidden without both modifiers")
controlDown = true
shiftDown = true
callbacks.Draw()
equal(hover, drawnHover, "Ctrl+Shift lights the hovered tile")
hoverPreviewEnabled = false
callbacks.Draw()
equal(nil, drawnHover, "disabled hover preview stays hidden with modifiers")
hoverPreviewEnabled = true
keyboardBlocked = true
callbacks.Draw()
equal(nil, drawnHover, "blocked keyboard input hides the hover")
keyboardBlocked = false

local addedEntry
local function readyMenu(entries)
    entries = entries or {
        { actionType = MiniMenuActionType.CANCEL, label = "Cancel" },
        { actionType = MiniMenuActionType.WALK, label = "Walk here" },
    }
    local menu = {
        entryCount = #entries,
        entries = entries,
        Add = function(self, label, action, ...)
            addedEntry = {
                label = label,
                action = action,
                args = table.pack(...),
            }
            table.insert(self.entries, 1, addedEntry)
            self.entryCount = #self.entries
        end,
        Swap = function(self, left, right)
            self.entries[left], self.entries[right]
                = self.entries[right], self.entries[left]
        end,
    }
    callbacks.MiniMenuReady({ miniMenu = menu })
    return menu
end

local function displayedLabels(menu)
    local labels = {}
    for index = #menu.entries, 1, -1 do
        labels[#labels + 1] = menu.entries[index].label
    end
    return table.concat(labels, "|")
end

local function findMenuEntry(menu, label)
    for _, entry in ipairs(menu.entries) do
        if entry.label == label then return entry end
    end
    return nil
end

local visibleSourceA = { name = "visible A" }
local visibleSourceB = { name = "visible B" }
queriedTiles = {
    [visibleSourceA] = {},
    [visibleSourceB] = {},
}
controlDown = false
shiftDown = false
addedEntry = nil
readyMenu({
    {
        actionType = MiniMenuActionType.CANCEL,
        label = "Unrelated interface action",
        fullText = "Unrelated interface action",
    },
})
equal(nil, addedEntry, "unrelated targets do not get the clear action")

local worldMapMenu = readyMenu({
    {
        actionType = MiniMenuActionType.CANCEL,
        label = "Cancel",
        fullText = "Cancel",
    },
    {
        label = "Open map settings",
        fullText = "Open map settings",
    },
    {
        label = "World Map",
        fullText = "World Map",
    },
})
equal(
    "World Map|Open map settings|Clear Visible Tilemarkers|New Preset from Visible Markers|Import Tilemarkers Preset|Cancel",
    displayedLabels(worldMapMenu),
    "world map actions are inserted directly above the native bottom option")
local clearEntry = findMenuEntry(worldMapMenu, "Clear Visible Tilemarkers")
local createVisibleEntry = findMenuEntry(
    worldMapMenu,
    "New Preset from Visible Markers")
local importEntry = findMenuEntry(worldMapMenu, "Import Tilemarkers Preset")
equal(true, clearEntry ~= nil, "world map gets the clear action")
equal(true, createVisibleEntry ~= nil, "world map gets visible preset creation")
equal(true, importEntry ~= nil, "world map gets preset import")
clearEntry.action()
equal(playerCoord, queriedCoord, "clear action queries around the player")
equal(30, queriedDistance, "clear action uses the drawing distance")
equal(2, promptedClearCount, "clear action prompts with the visible marker count")
equal(nil, clearedSources, "markers remain until the prompt is confirmed")
clearConfirmation()
equal(2, #clearedSources, "confirmation removes every visible editable marker")
local cleared = {}
for _, coord in ipairs(clearedSources) do cleared[coord] = true end
equal(true, cleared[visibleSourceA], "clear action includes the first visible marker")
equal(true, cleared[visibleSourceB], "clear action includes the second visible marker")

createVisibleEntry.action()
equal(true, promptedPresetCreationVisible, "world map action opens visible preset popup")
importEntry.action()
equal(true, promptedPresetImport, "world map import action opens import popup")
clearedSources = nil
equal(
    true,
    initializedPresetHandlers.createVisible("Visible route"),
    "visible preset handler succeeds")
equal("Visible route", createdPresetName, "visible preset keeps submitted name")
equal(visibleExportTiles, createdPresetTiles, "visible preset uses coordinate export")
equal(2, #exportedCoords, "visible preset exports every visible marker")
equal(2, #clearedSources, "visible preset removes only exported source markers")

addedEntry = nil
readyMenu({
    {
        label = "World Map",
        verbText = "World Map",
    },
})
equal(
    "Import Tilemarkers Preset",
    addedEntry.label,
    "world map verb text gets all plugin actions")

queriedTiles = {}
controlDown = true
shiftDown = true

local orderedMenu = readyMenu()
equal("Mark tile", addedEntry.label, "unmarked tile gets a mark entry")
equal(
    "Walk here|Mark tile|Cancel",
    displayedLabels(orderedMenu),
    "mark action renders immediately below the native top entry")
local selectedEntry = addedEntry
local locMenu = readyMenu({
    { actionType = MiniMenuActionType.CANCEL, label = "Cancel" },
    { actionType = MiniMenuActionType.WALK, label = "Walk here" },
    { actionType = MiniMenuActionType.OP_LOC2, label = "Examine" },
    { actionType = MiniMenuActionType.OP_LOC1, label = "Open" },
})
equal(
    "Open|Mark tile|Examine|Walk here|Cancel",
    displayedLabels(locMenu),
    "mark action follows the top loc option without reordering native entries")
local movedHover = { name = "tile behind menu" }
miniMenuOpen = true
cursorHover = movedHover
mousePosition = { x = 240, y = 180 }
controlDown = false
callbacks.Draw()
equal(hover, drawnHover, "open menu keeps the tile that created its entries highlighted")
controlDown = true
miniMenuOpen = false
callbacks.MiniMenuClosed({})
callbacks.Draw()
equal(nil, drawnHover, "menu selection position is not previewed as another marker")
addedEntry = nil
readyMenu()
equal(nil, addedEntry, "menu selection position does not create a follow-up tile action")
mousePosition = { x = 245, y = 180 }
callbacks.Draw()
equal(movedHover, drawnHover, "moving away from the menu selection restores live highlighting")
cursorHover = hover
selectedEntry.action(table.unpack(selectedEntry.args, 1, selectedEntry.args.n))
equal(source, addedSource, "mark action stores the canonical tile")
equal(0x12345678, addedMetadata.outlineColour, "mark action stores selected outline")
equal(0x0E2A4542, addedMetadata.fillColour, "mark action stores derived fill")
equal(0x12345678, rememberedColour, "mark action records its colour as recent")
equal(nil, labelledSource, "mark action does not open customization")

local markedMenu = readyMenu()
equal(
    "Walk here|Unmark tile|Customize Tile|Cancel",
    displayedLabels(markedMenu),
    "marked tile actions render together below the native top entry")
local colourEntry = markedMenu.entries[2]
local unmarkEntry = markedMenu.entries[3]
colourEntry.action(table.unpack(colourEntry.args, 1, colourEntry.args.n))
equal("Existing label", promptedInitialLabel, "customization starts from tile label")
equal(0x12345678, promptedInitialColour, "colour prompt starts from tile colour")
equal(false, promptedInitialFill, "colour prompt starts from tile fill state")
equal(
    false,
    promptedInitialOutlineCornersOnly,
    "colour prompt starts from tile corner outline state")
promptedCustomizationActions.preview("Preview label", 0xAABBCCDD, true, true)
equal(source, previewedSource, "customization preview targets the marked canonical tile")
equal("Preview label", previewedLabel, "label changes reach the live preview")
equal(0xAABBCCDD, previewedColour, "colour changes reach the live preview")
equal(true, previewedFill, "fill changes reach the live preview")
equal(true, previewedOutlineCornersOnly, "corner changes reach the live preview")
promptedCustomizationActions.cancel()
equal(source, cancelledPreviewSource, "cancel clears the marked tile preview")
equal("Existing label", existingLabel, "cancel preserves the pre-edit label")
equal(0x12345678, existingColour, "cancel preserves the pre-edit colour")
equal(false, existingFill, "cancel preserves the pre-edit fill state")
equal(false, existingOutlineCornersOnly, "cancel preserves pre-edit corners")

colourEntry.action(table.unpack(colourEntry.args, 1, colourEntry.args.n))
promptedCustomizationActions.preview("Updated label", 0x445566FF, true, true)
promptedCustomizationActions.confirm("Updated label", 0x445566FF, true, true)
equal(source, recolouredSource, "colour action targets the marked canonical tile")
equal(source, labelledSource, "customization label targets the marked canonical tile")
equal("Updated label", labelledText, "confirmed customization stores its label")
equal(0x445566FF, recolouredValue, "confirmed tile colour is stored")
equal(true, recolouredFill, "confirmed fill state is stored")
equal(true, recolouredOutlineCornersOnly, "confirmed corner outline is stored")
unmarkEntry.action(table.unpack(unmarkEntry.args, 1, unmarkEntry.args.n))
equal(source, removedSource, "unmark action removes the canonical tile")

presetAtSource = {
    id = "preset_1",
    name = "Editable",
}
local presetMarkedMenu = readyMenu()
equal(
    "Walk here|Edit in preset|Cancel",
    displayedLabels(presetMarkedMenu),
    "preset-owned tile replaces the mark action with preset editing")
local editPresetEntry = findMenuEntry(presetMarkedMenu, "Edit in preset")
editPresetEntry.action(table.unpack(editPresetEntry.args, 1, editPresetEntry.args.n))
equal("preset_1", startedPresetEditID, "preset tile opens its owning preset")
equal("Editable", startedPresetEditName, "preset edit overlay receives the preset name")
equal(true, editActive, "preset tile action immediately enters edit mode")
equal(true, initializedPresetHandlers.cancelEdit(), "preset tile edit can be cancelled")
equal(false, editActive, "cancel leaves preset edit mode")
presetAtSource = nil

addedEntry = nil
promptOpen = true
readyMenu()
equal(nil, addedEntry, "customization prompt suppresses tile menu entries")

promptOpen = false
equal(true, initializedPresetHandlers.startEdit("preset_1"), "preset edit handler starts")
callbacks.Draw()
equal("preset_1", excludedPresetID, "draw excludes the saved copy of the edited preset")
equal("Working copy", drawnTiles[hover].text, "draw includes the preset working copy")
editMarked = false
local editAddMenu = readyMenu()
equal(
    "Walk here|Add to preset|Cancel",
    displayedLabels(editAddMenu),
    "edit mode offers to add an unmarked preset tile")
local editAddEntry = findMenuEntry(editAddMenu, "Add to preset")
editAddEntry.action(table.unpack(editAddEntry.args, 1, editAddEntry.args.n))
equal(source, editAddedSource, "edit add targets the canonical source tile")
local editRemoveMenu = readyMenu()
equal(
    "Walk here|Remove from preset|Customize Tile|Cancel",
    displayedLabels(editRemoveMenu),
    "edit mode offers remove and customization for preset tiles")
local editRemoveEntry = findMenuEntry(editRemoveMenu, "Remove from preset")
editRemoveEntry.action(table.unpack(editRemoveEntry.args, 1, editRemoveEntry.args.n))
equal(source, editRemovedSource, "edit remove targets the canonical source tile")
equal(true, initializedPresetHandlers.saveEdit(), "save handler commits preset edits")
equal("preset_1", updatedPresetID, "save targets the edited preset")
equal(3300, updatedPresetTiles[1].x, "save commits the working tile set")
equal(false, editActive, "successful save leaves preset edit mode")

print("test_interaction: ok")
