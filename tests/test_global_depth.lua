package.path = "./?.lua;" .. package.path

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local storedRecentColours
local storedHoverPreview
PersistentDB = {
    GetString = function() return nil end,
    GetInt = function(_, key)
        if key == "markerFontSize" then return 19 end
        if key == "markerOutlineThicknessTenths" then return 35 end
        return nil
    end,
    GetBool = function(_, key)
        if key == "markerIgnoreDepth" then return true end
        return nil
    end,
    SetBool = function(_, key, value)
        if key == "markerHoverPreview" then storedHoverPreview = value end
        return true
    end,
    SetString = function(_, key, value)
        if key == "recentMarkerColours" then storedRecentColours = value end
        return true
    end,
}

config = { Obj = { ROOFTILE = 1 } }
id = {
    Font = {
        MUSEO_SANS_15PT_REGULAR = "font_15",
        MUSEO_SANS_19PT_REGULAR = "font_19",
        MUSEO_SANS_11PT_REGULAR = "font_11",
    },
}
ScreenConvert = {
    CoordFineToScreen = function() return { x = 100, y = 100 } end,
}

ui = {
    AlignMode = {
        CENTRE = 1,
    },
    TextDataConfig = {
        new = function() return {} end,
    },
}

local submitted = {}
local label
local promptButtons
local promptButtonOptions
local promptInput
local promptTexts
local promptWindowOptions
local promptColourPicker
local promptColourPickerOptions
local promptList
local promptListOptions
local promptCheckboxEntries
local promptCheckboxOptions
local promptControlOrder
local prettyui = {
    RibbonBar = {
        Register = function()
            return { SetActive = function() end }
        end,
    },
    Window = {
        new = function(_, options)
            promptWindowOptions = options
            local window = { root = {} }
            promptButtons = {}
            promptButtonOptions = {}
            promptTexts = {}
            promptControlOrder = {}
            function window:AddText(value)
                local options = type(value) == "table"
                    and value or { text = tostring(value or "") }
                promptTexts[#promptTexts + 1] = options
            end
            function window:AddTextField(fieldOptions)
                promptControlOrder[#promptControlOrder + 1] = "input"
                local field = { value = fieldOptions.text or "", options = fieldOptions }
                function field:GetText() return self.value end
                promptInput = field
                return field
            end
            function window:AddColourPicker(pickerOptions)
                promptControlOrder[#promptControlOrder + 1] = "picker"
                promptColourPickerOptions = pickerOptions
                local picker = { value = pickerOptions.value }
                function picker:GetValue() return self.value end
                function picker:SetValue(value, notify)
                    self.value = value
                    if notify ~= false and pickerOptions.onChange then
                        pickerOptions.onChange(self, value)
                    end
                end
                promptColourPicker = picker
                return picker
            end
            function window:AddCheckboxButton(entries, checkboxOptions)
                promptControlOrder[#promptControlOrder + 1] = "fill"
                promptCheckboxEntries = entries
                promptCheckboxOptions = checkboxOptions
                return {}
            end
            function window:AddList(listOptions)
                promptControlOrder[#promptControlOrder + 1] = "recent"
                promptListOptions = listOptions
                local list = { entries = listOptions.entries or {} }
                function list:SetEntries(entries) self.entries = entries end
                promptList = list
                return list
            end
            function window:AddFancyButton(content, action, buttonOptions)
                promptButtons[content] = action
                promptButtonOptions[content] = buttonOptions
            end
            function window:Close()
                if options.onClose then options.onClose(self) end
                self.root = nil
            end
            function window:Destroy()
                self.root = nil
            end
            return window
        end,
    },
}
local draw = {
    Tile = function(settings)
        submitted[#submitted + 1] = settings
        return true
    end,
}

package.loaded["src/ui"] = nil
local UI = require("src/ui")
UI:init({}, prettyui, draw)
expect(UI:getStyle().fill, false, "new marker fill defaults off")
expect(UI:isHoverPreviewEnabled(), true, "hover preview defaults on")
UI.canvas = {
    Clear = function() end,
    AddText = function(_, x, y, width, height, text, textConfig)
        label = {
            x = x,
            y = y,
            width = width,
            height = height,
            text = text,
            textConfig = textConfig,
        }
    end,
}

local coord = {
    level = 0,
    x = 10,
    z = 10,
    ToPacked = function() return 123 end,
    ToCoordFine = function()
        return {}
    end,
}

expect(UI:drawTile(coord, {
    text = "Global label",
}), true, "tile draws")
expect(submitted[1].ignoreDepth, true, "global draw-over-scenery setting reaches renderer")
expect(submitted[1].outlineThickness, 3.5, "global outline thickness reaches renderer")
expect(label.textConfig.font, "font_19", "global label size reaches rendered labels")
expect(label.textConfig.rgba, 0xE4B3FFFF, "label is brighter than its outline")

submitted = {}
local sameTileHover = {
    level = 0,
    x = 10,
    z = 10,
    ToPacked = function() return 123 end,
    ToCoordFine = function() return {} end,
}
UI:draw({
    [coord] = {
        outlineColour = 0x00FFFFFF,
        fillColour = 0x00FFFF20,
        fill = true,
        outlineThickness = 4.0,
        outlineCornersOnly = true,
        text = "Existing",
    },
}, sameTileHover)

expect(#submitted, 1, "hovered existing tile is submitted only once")
expect(submitted[1].outlineColour, 0x4DFFFFFF, "marked hover lightens its outline colour")
expect(submitted[1].fillColour, 0x4DFFFF20, "marked hover lightens its fill colour")
expect(submitted[1].outlineThickness, 3.5, "hover uses global thickness")
expect(submitted[1].outlineCornersOnly, true, "corner-only outline reaches renderer")
expect(label.text, "Existing", "hover preserves the existing marker label")
expect(label.textConfig.rgba, 0xA8FFFFFF, "hovered label is brighter than its outline")

submitted = {}
local emptyHover = {
    level = 0,
    x = 11,
    z = 10,
    ToPacked = function() return 456 end,
    ToCoordFine = function() return {} end,
}
UI:draw({ [coord] = {} }, emptyHover)
expect(#submitted, 2, "unplaced hover draws beside the existing marker")
local emptySubmission
for _, settings in ipairs(submitted) do
    if settings.coordGrid == emptyHover then emptySubmission = settings end
end
expect(emptySubmission.outlineColour, 0xFFFFFF90, "empty hover uses a subtle white outline")
expect(emptySubmission.fillColour, 0xFFFFFF38, "empty hover uses a subtle white fill")

submitted = {}
local eastCoord = {
    level = 0,
    x = 11,
    z = 10,
    ToPacked = function() return 124 end,
    ToCoordFine = function() return {} end,
}
UI:draw({
    [coord] = { outlineColour = 0x00FFFFFF },
    [eastCoord] = { outlineColour = 0xFF00FFFF },
}, nil)
expect(#submitted, 2, "neighbouring tiles are both submitted to PrettyUI")

UI.gameArea = { width = 800, height = 600 }
local clearConfirmed = false
expect(UI:promptForClear(27, function()
    clearConfirmed = true
end), true, "clear confirmation opens")
expect(UI:isPromptOpen(), true, "clear confirmation is tracked")
expect(promptWindowOptions.height, 136, "clear confirmation uses compact height")
expect(promptWindowOptions.width, 416, "clear confirmation fits the longer message")
expect(#promptTexts, 1, "clear confirmation uses one continuous text component")
expect(
    promptTexts[1].text,
    "Are you sure you wish to clear <col=F2C66D>27</col> tilemarkers?",
    "clear confirmation highlights the count without layout gaps")
expect(promptButtonOptions.Yes.inline, nil, "yes starts the confirmation action row")
expect(promptButtonOptions.Yes.width, 184, "yes fills the wider action row")
expect(promptButtonOptions.No.width, 184, "no fills the wider action row")
expect(promptButtonOptions.No.inline, true, "no shares the confirmation action row")
promptButtons.No()
expect(clearConfirmed, false, "no leaves visible markers unchanged")
expect(UI:isPromptOpen(), false, "declined clear confirmation closes")

expect(UI:promptForClear(2, function()
    clearConfirmed = true
end), true, "second clear confirmation opens")
promptButtons.Yes()
expect(clearConfirmed, true, "yes confirms visible marker removal")
expect(UI:isPromptOpen(), false, "accepted clear confirmation closes")

local acceptedColour
local acceptedFill
local acceptedOutlineCornersOnly
local acceptedLabel
local previewedColour
local previewedFill
local previewedOutlineCornersOnly
local previewedLabel
expect(UI:promptForCustomization("Existing label", 0x11223380, false, false, {
    preview = function(labelValue, value, fill, outlineCornersOnly)
        previewedLabel = labelValue
        previewedColour = value
        previewedFill = fill
        previewedOutlineCornersOnly = outlineCornersOnly
    end,
    confirm = function(labelValue, value, fill, outlineCornersOnly)
        acceptedLabel = labelValue
        acceptedColour = value
        acceptedFill = fill
        acceptedOutlineCornersOnly = outlineCornersOnly
    end,
}), true, "colour prompt opens")
expect(promptWindowOptions.title, "Tile customization", "customization window uses its new title")
expect(promptWindowOptions.height, 416, "customization window fits its label and style controls")
expect(UI:isPromptOpen(), true, "open colour prompt is tracked")
expect(promptInput.value, "Existing label", "customization prepopulates the tile label")
expect(promptInput.options.placeholder, "Tile label (optional)", "label field explains that it is optional")
expect(promptColourPicker.value, 0x11223380, "colour prompt starts from tile colour")
expect(promptColourPickerOptions.alphaSlider, true, "colour prompt exposes opacity")
expect(promptCheckboxEntries[1].text, "Render fill", "colour prompt labels fill control")
expect(promptCheckboxEntries[1].selected, false, "colour prompt starts from tile fill state")
expect(
    promptCheckboxEntries[2].text,
    "Draw outline corners only",
    "colour prompt labels corner outline control")
expect(
    promptCheckboxEntries[2].selected,
    false,
    "colour prompt starts from tile corner outline state")
expect(table.concat(promptControlOrder, ","), "input,fill,picker,recent", "label is the first customization control")
expect(promptListOptions.height, 122, "recent list fits five rows without scrolling")
promptInput.value = "  Safe tile  "
promptInput.options.onChange()
promptCheckboxOptions.onChange(nil, nil, "render_fill", true)
promptCheckboxOptions.onChange(nil, nil, "outline_corners_only", true)
promptColourPicker:SetValue(0x445566FF)
expect(previewedLabel, "Safe tile", "label edits preview immediately")
expect(previewedColour, 0x445566FF, "colour edits preview immediately")
expect(previewedFill, true, "fill edits preview immediately")
expect(previewedOutlineCornersOnly, true, "corner edits preview immediately")
promptButtons.Confirm()
expect(acceptedLabel, "Safe tile", "confirmed customization trims and returns its label")
expect(acceptedColour, 0x445566FF, "confirmed colour is returned")
expect(acceptedFill, true, "confirmed fill choice is returned")
expect(acceptedOutlineCornersOnly, true, "confirmed corner outline is returned")
expect(storedRecentColours, "445566FF", "confirmed colour is persisted as recent")

UI:rememberColour(0xAABBCCDD)
local cancelledCustomization = false
local unexpectedlyConfirmed = false
expect(UI:promptForCustomization("Keep me", 0x010203FF, true, true, {
    confirm = function()
        unexpectedlyConfirmed = true
    end,
    preview = function() end,
    cancel = function()
        cancelledCustomization = true
    end,
}), true, "second colour prompt opens")
expect(#promptList.entries, 2, "recent colours render as list rows")
expect(promptList.entries[1].backgroundColour, 0xAABBCCDD, "newest row uses its colour")
expect(promptList.entries[1].text, "", "recent rows do not expose hex text")
promptListOptions.onChange(promptList, 2, true)
expect(promptColourPicker.value, 0x445566FF, "recent colour row updates colour picker")
promptButtons.Cancel()
expect(cancelledCustomization, true, "cancel invokes customization rollback")
expect(unexpectedlyConfirmed, false, "cancel does not confirm customization")
expect(UI:isPromptOpen(), false, "cancelled colour prompt closes")

local closeCancelled = false
expect(UI:promptForCustomization("Keep me", 0x010203FF, true, true, {
    cancel = function()
        closeCancelled = true
    end,
}), true, "third colour prompt opens")
UI.colourPromptWindow:Close()
expect(closeCancelled, true, "window close invokes customization rollback")
expect(UI:isPromptOpen(), false, "closed colour prompt is cleared")

for index = 1, 6 do
    UI:rememberColour((index << 24) | 0x000000FF)
end
expect(#UI.recentColours, 5, "recent colour history is capped")
expect(UI.recentColours[1], 0x060000FF, "newest recent colour stays first")
expect(UI.recentColours[5], 0x020000FF, "oldest retained colour stays last")

local createdPresetName
local createdVisiblePresetName
local importedPresetToken
local renamedPresetID
local renamedPresetName
local deletedPresetID
UI.presetHandlers = {
    list = function() return {} end,
    isActive = function() return false end,
    setActive = function() return true end,
    delete = function(id)
        deletedPresetID = id
        return true
    end,
    create = function(name)
        createdPresetName = name
        return true, { id = "created_preset", name = name }
    end,
    createVisible = function(name)
        createdVisiblePresetName = name
        return true, { id = "visible_preset", name = name }
    end,
    import = function(token)
        importedPresetToken = token
        return true, { id = "imported_preset", name = "Imported" }
    end,
    rename = function(id, name)
        renamedPresetID = id
        renamedPresetName = name
        return true
    end,
    export = function()
        return true, "TM2export"
    end,
}

expect(UI:promptForPresetCreation(false), true, "add preset popup opens")
expect(promptWindowOptions.title, "Add preset", "add preset popup is titled")
promptInput.value = "  New route  "
promptButtons.Save()
expect(createdPresetName, "New route", "add preset popup trims and saves its name")

expect(UI:promptForPresetCreation(true), true, "visible preset popup opens")
expect(
    promptWindowOptions.title,
    "New preset from visible markers",
    "visible preset popup is titled")
promptInput.value = "Visible route"
promptButtons.Save()
expect(
    createdVisiblePresetName,
    "Visible route",
    "visible preset popup uses visible creation handler")

expect(UI:promptForPresetImport(), true, "import preset popup opens")
expect(promptWindowOptions.height, 176, "import popup fits its content")
promptInput.value = "TM2import"
promptButtons.Import()
expect(importedPresetToken, "TM2import", "import popup submits its token")

expect(UI:promptForPresetRename("preset_1", "Old name"), true, "rename popup opens")
expect(promptInput.value, "Old name", "rename popup prepopulates the preset name")
promptInput.value = "New name"
promptButtons.Rename()
expect(renamedPresetID, "preset_1", "rename popup targets its preset")
expect(renamedPresetName, "New name", "rename popup submits the new name")

expect(UI:promptForPresetDelete("preset_1", "New name"), true, "delete popup opens")
expect(
    promptTexts[1].text,
    "Are you sure you want to delete \"New name\"? This cannot be undone.",
    "delete popup names the preset and warns")
promptButtons.Cancel()
expect(deletedPresetID, nil, "cancel keeps the preset")

expect(UI:promptForPresetDelete("preset_1", "New name"), true, "delete popup reopens")
promptButtons.Delete()
expect(deletedPresetID, "preset_1", "delete confirmation removes the preset")

expect(
    UI:promptForPresetExport("preset_1", "New name"),
    true,
    "export preset popup opens")
expect(promptWindowOptions.height, 192, "export popup fits its content")
expect(
    promptTexts[1].text,
    "Click the field below, press <col=F2C66D>Ctrl+A</col> to select the full export string, then press <col=F2C66D>Ctrl+C</col> to copy it.",
    "export popup explains keyboard copy workflow")
expect(promptInput.value, "TM2export", "export popup exposes the preset token")
promptButtons.Close()

local mountedTabs
local mountedPages = {}
local editOverlay
local editOverlayOptions
local makeControl
makeControl = function()
    local control = {
        content = { content = "" },
        addedControls = {},
        addedComponents = {},
    }
    control.root = control

    local function addControl(self)
        local child = makeControl()
        self.addedComponents[#self.addedComponents + 1] = child
        return child
    end
    control.AddCheckboxButton = function(self, entries, options)
        self.addedControls[#self.addedControls + 1] = "checkbox"
        local child = addControl(self)
        child.entries = entries
        child.options = options
        return child
    end
    control.AddColourPicker = addControl
    control.AddComboBox = addControl
    control.AddList = addControl
    control.AddFancyButton = function(self, text, action, options)
        self.addedControls[#self.addedControls + 1] = "button:" .. text
        local child = addControl(self)
        child.text = text
        child.action = action
        child.options = options
        return child
    end
    control.AddPanel = function(self, options)
        self.addedControls[#self.addedControls + 1] = "panel"
        local child = addControl(self)
        child.options = options
        return child
    end
    control.AddSimpleButton = addControl
    control.AddSlider = addControl
    control.AddSpriteButton = function(self, sprite, action, options)
        self.addedControls[#self.addedControls + 1] = "sprite:" .. sprite
        local child = addControl(self)
        child.sprite = sprite
        child.action = action
        child.options = options
        return child
    end
    control.AddTabs = function(_, entries)
        mountedTabs = entries
        return makeControl()
    end
    control.AddText = function(self, options)
        self.addedControls[#self.addedControls + 1] = "text"
        local child = addControl(self)
        child.options = options
        return child
    end
    control.AddTextField = addControl
    control.GetPage = function(_, index)
        mountedPages[index] = mountedPages[index] or makeControl()
        return mountedPages[index]
    end
    control.Close = function() end
    control.Select = function() end
    control.SetActive = function() end
    control.SetDisabled = function() end
    control.SetEntries = function() end
    control.SetSelected = function() end
    control.SetText = function() end
    control.Show = function() end
    control.SetScrollPosition = function(self, position)
        self.scrollY = position
        self.restoredScrollY = position
    end
    control.ScrollToChild = function(self, child)
        self.scrolledToChild = child
    end
    control.Destroy = function(self) self.destroyed = true end
    control.MoveToFront = function(self) self.movedToFront = true end
    control.RefreshRowBackgrounds = function(self)
        self.rowBackgroundsRefreshed = true
    end
    return control
end

UI.prettyui = {
    Window = {
        new = function()
            return makeControl()
        end,
    },
    Panel = {
        new = function(_, options)
            editOverlayOptions = options
            editOverlay = makeControl()
            return editOverlay
        end,
    },
}
local mountedPreset = { id = "preset_1", name = "My preset" }
UI.presetHandlers = {
    list = function() return { mountedPreset } end,
    isActive = function() return true end,
    setActive = function() return true end,
    delete = function() return true end,
    export = function() return true, "TM2token" end,
    rename = function() return true end,
    import = function() return true end,
    create = function() return true end,
    createVisible = function() return true end,
    startEdit = function(id)
        expect(id, "preset_1", "edit starts for the selected preset")
        return true
    end,
    saveEdit = function() return true, "Saved" end,
    cancelEdit = function() return true end,
}
UI.gameArea = { width = 800, height = 600 }
UI:buildWindow()
expect(UI.window ~= nil, true, "settings window mounts")
expect(#mountedTabs, 2, "settings window exposes two tabs")
expect(mountedTabs[1].value, "markers", "markers tab remains first")
expect(mountedTabs[2].value, "presets", "presets tab combines management and transfer")
expect(UI.thicknessSlider ~= nil, true, "outline controls mount on the markers page")
expect(UI.ignoreDepthCheckbox ~= nil, true, "depth control mounts on the markers page")
expect(mountedPages[1].addedControls[1], "checkbox", "draw-over-scenery is first")
local markerOptions = mountedPages[1].addedComponents[1]
expect(
    markerOptions.entries[2].value,
    "hover_preview",
    "hover preview toggle is available")
expect(markerOptions.entries[2].selected, true, "hover preview toggle defaults on")
expect(markerOptions.options.inline, true, "marker toggles share one row")
markerOptions.options.onChange(nil, nil, "hover_preview", false)
expect(UI:isHoverPreviewEnabled(), false, "hover preview toggle updates runtime state")
expect(storedHoverPreview, false, "hover preview toggle persists")
expect(UI.labelSizeCombo ~= nil, true, "label size control mounts on the markers page")
expect(
    table.concat(mountedPages[2].addedControls, ","),
    "text,sprite:PLUS,sprite:IMPORT,panel",
    "preset tab starts with add/import controls and a preset panel")
local mountedPresetPanel = mountedPages[2].addedComponents[4]
expect(
    table.concat(mountedPresetPanel.addedControls, ","),
    "sprite:PENCIL,text,sprite:EYE,sprite:SETTINGS,sprite:EXPORT,sprite:TRASH",
    "rename precedes the title and remaining actions stay below")
expect(mountedPresetPanel.options.height, 96, "preset panel fits both styled rows")
expect(mountedPresetPanel.options.layout.startY, 10, "title row is vertically centred")
expect(mountedPresetPanel.options.layout.paddingBottom, 0, "panel layout uses full height")
expect(
    mountedPresetPanel.addedComponents[2].options.inline,
    true,
    "preset title follows rename on the same row")
expect(
    mountedPresetPanel.addedComponents[3].options.marginTop,
    12,
    "action icons are vertically centred in lower row")
expect(
    mountedPresetPanel.addedComponents[3].options.x,
    202,
    "bottom action icons align to the right")
expect(
    mountedPresetPanel.addedComponents[4].options.tooltip,
    "Edit preset tiles",
    "preset settings action explains tile editing")
expect(
    mountedPresetPanel.options.rowBackgroundColours[1],
    0x24211EFF,
    "preset title row uses settings backdrop")
expect(
    mountedPresetPanel.options.rowBackgroundColours[2],
    0x2E2825FF,
    "preset button row uses alternate backdrop")
expect(
    mountedPresetPanel.options.rowBackgroundEdgeToEdge,
    true,
    "preset row backdrops retain edge-to-edge styling")
expect(mountedPresetPanel.rowBackgroundsRefreshed, true, "preset row backdrops refresh")
mountedPages[2].scrollY = 120
mountedPresetPanel.addedComponents[3].action()
expect(
    mountedPages[2].restoredScrollY,
    120,
    "preset toggle restores the previous scroll position")
UI:rebuildPresetPanels("preset_1")
expect(
    mountedPages[2].scrolledToChild,
    UI.presetPanelsByID.preset_1,
    "new preset focus scrolls its panel into view")

mountedPresetPanel.addedComponents[4].action()
expect(editOverlay ~= nil, true, "edit action mounts a PrettyUI panel overlay")
expect(editOverlayOptions.backgroundAlpha, 0.78, "edit overlay is semitransparent")
expect(editOverlay.root.movedToFront, true, "edit overlay is raised above game UI")
expect(
    table.concat(editOverlay.addedControls, ","),
    "text,text,button:Save,button:Cancel",
    "edit overlay clearly presents its status and actions")
editOverlay.addedComponents[4].action()
expect(editOverlay.destroyed, true, "cancel destroys the edit overlay")
expect(UI.presetEditOverlay, nil, "cancel exits UI edit mode")

UI.presetHandlers.saveEdit = function()
    return false, "A preset must contain at least one tile."
end
UI.presetPanelsByID.preset_1.addedComponents[4].action()
local failedSaveOverlay = editOverlay
failedSaveOverlay.addedComponents[3].action()
expect(
    UI.presetEditOverlay,
    failedSaveOverlay,
    "failed save keeps preset edit mode open")
expect(
    failedSaveOverlay.addedComponents[2].content,
    "A preset must contain at least one tile.",
    "failed save explains the problem in the overlay")
failedSaveOverlay.addedComponents[4].action()


print("test_global_config: ok")
