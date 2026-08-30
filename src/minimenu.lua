local RegionBindings = require("src/region_bindings")
local Tiles = require("src/tiles")
local UI = require("src/ui")

local Minimenu = {}

local EVENT_ID = "tileMarker"
local MENU_CURSOR_DEAD_ZONE_SQUARED = 16

local menuHover = nil
local suppressedMousePosition = nil
local started = false
local actions = {}

local function hoveredTile()
    if not Mouse.IsAvailable() then
        return nil
    end

    local mousePosition = Mouse.GetPosition()
    if mousePosition == nil then
        return nil
    end

    if suppressedMousePosition ~= nil then
        local deltaX = mousePosition.x - suppressedMousePosition.x
        local deltaY = mousePosition.y - suppressedMousePosition.y
        if deltaX * deltaX + deltaY * deltaY
                <= MENU_CURSOR_DEAD_ZONE_SQUARED then
            return nil
        end
        suppressedMousePosition = nil
    end

    return ScreenConvert.ScreenToCoordGrid(mousePosition)
end

local function markingModifiersDown()
    return Keyboard.IsAvailable()
        and not Keyboard.IsBlocked()
        and Keyboard.IsControlDown()
        and Keyboard.IsShiftDown()
end

local function moveBelowNativeTop(miniMenu, nativeEntryCount, customCount)
    if nativeEntryCount < 1 or customCount < 1 then return end
    local totalEntryCount = nativeEntryCount + customCount
    for customIndex = customCount, 1, -1 do
        local targetIndex = totalEntryCount - customCount + customIndex - 1
        for index = customIndex, targetIndex - 1 do
            miniMenu:Swap(index, index + 1)
        end
    end
end

local function moveAboveNativeBottom(miniMenu, nativeEntryCount, customCount)
    if nativeEntryCount < 1 or customCount < 1 then return end
    for index = customCount + 1, 2, -1 do
        miniMenu:Swap(index, index - 1)
    end
end

local function isWorldMapText(value)
    if type(value) ~= "string" then
        return false
    end
    local plainText = value:gsub("<.->", ""):match("^%s*(.-)%s*$")
    return plainText:lower() == "world map"
end

local function appendWorldMapAction(miniMenu)
    for _, entry in ipairs(miniMenu.entries) do
        if isWorldMapText(entry.overrideText)
                or isWorldMapText(entry.fullText)
                or isWorldMapText(entry.verbText) then
            local nativeEntryCount = miniMenu.entryCount
            local customCount = 0
            if actions.clearVisible ~= nil then
                miniMenu:Add("Clear Visible Tilemarkers", actions.clearVisible)
                customCount = customCount + 1
            end
            if actions.createVisiblePreset ~= nil then
                miniMenu:Add(
                    "New Preset from Visible Markers",
                    actions.createVisiblePreset)
                customCount = customCount + 1
            end
            if actions.importPreset ~= nil then
                miniMenu:Add("Import Tilemarkers Preset", actions.importPreset)
                customCount = customCount + 1
            end
            moveAboveNativeBottom(miniMenu, nativeEntryCount, customCount)
            return true
        end
    end
    return false
end

local function setTileMarked(store, source, marked)
    if not marked then
        store:remove(source)
        return
    end

    local style = UI:getStyle()
    store:add(source, {
        outlineColour = style.outlineColour,
        fillColour = style.fillColour,
        fill = style.fill,
    })
    UI:rememberColour(style.outlineColour)
end

local function customizeTile(store, source)
    local currentLabel = store:getLabel(source) or ""
    local currentColour = store:getColour(source) or UI:getStyle().outlineColour
    local currentFill = store:getFill(source)
    local currentOutlineCornersOnly = store:getOutlineCornersOnly(source)
    UI:promptForCustomization(
        currentLabel,
        currentColour,
        currentFill,
        currentOutlineCornersOnly,
        {
            preview = function(label, colour, fill, outlineCornersOnly)
                store:previewCustomization(
                    source, label, colour, fill, outlineCornersOnly)
            end,
            confirm = function(label, colour, fill, outlineCornersOnly)
                store:setCustomization(
                    source, label, colour, fill, outlineCornersOnly)
            end,
            cancel = function()
                store:cancelCustomizationPreview(source)
            end,
        })
end

local function onReady(miniMenuReadyEvent)
    local miniMenu = miniMenuReadyEvent.miniMenu
    local editStore = actions.editStore and actions.editStore() or nil
    if editStore == nil and appendWorldMapAction(miniMenu) then
        menuHover = nil
        suppressedMousePosition = nil
        return
    end

    if not markingModifiersDown() or UI:isPromptOpen() then
        menuHover = nil
        suppressedMousePosition = nil
        return
    end

    local target = hoveredTile()
    if target == nil then
        menuHover = nil
        return
    end
    menuHover = target

    local source = RegionBindings.toSource(target)
    local store = editStore or Tiles
    local preset = editStore == nil
        and actions.findPresetAt ~= nil
        and actions.findPresetAt(source)
        or nil

    local nativeEntryCount = miniMenu.entryCount
    local customCount = 1
    if preset ~= nil and actions.startPresetEdit ~= nil then
        miniMenu:Add(
            "Edit in preset",
            actions.startPresetEdit,
            preset.id,
            preset.name)
    elseif store:contains(source) then
        -- Add prepends each custom entry, so add higher priority first.
        miniMenu:Add(
            editStore and "Remove from preset" or "Unmark tile",
            setTileMarked,
            store,
            source,
            false)
        miniMenu:Add("Customize Tile", customizeTile, store, source)
        customCount = 2
    else
        miniMenu:Add(
            editStore and "Add to preset" or "Mark tile",
            setTileMarked,
            store,
            source,
            true)
    end

    moveBelowNativeTop(miniMenu, nativeEntryCount, customCount)
end

local function onClosed()
    menuHover = nil
    local mousePosition = Mouse.IsAvailable() and Mouse.GetPosition() or nil
    suppressedMousePosition = mousePosition and {
        x = mousePosition.x,
        y = mousePosition.y,
    } or nil
end

function Minimenu.getHover()
    local menuOpen = MiniMenu.IsOpen()
    local modifiersDown = markingModifiersDown()
    if not menuOpen and not modifiersDown then
        suppressedMousePosition = nil
    end

    if menuOpen then
        return menuHover
    end
    if modifiersDown then
        return hoveredTile()
    end
    return nil
end

function Minimenu.reset()
    menuHover = nil
    suppressedMousePosition = nil
end

function Minimenu.start(menuActions)
    actions = menuActions or {}
    if started then
        return
    end
    started = true
    Event.MiniMenuReady.Subscribe(EVENT_ID, onReady)
    Event.MiniMenuClosed.Subscribe(EVENT_ID, onClosed)
end

function Minimenu.shutdown()
    if not started then
        return
    end
    started = false
    Event.MiniMenuReady.Unsubscribe(EVENT_ID)
    Event.MiniMenuClosed.Unsubscribe(EVENT_ID)
    actions = {}
    Minimenu.reset()
end

return Minimenu
