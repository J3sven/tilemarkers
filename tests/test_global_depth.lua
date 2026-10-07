package.path = "./?.lua;" .. package.path
log = print

local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local storedRecentColours
local storedHoverPreview
local storedRendering = {}
local storedMarkingKeybind
GameKey = { CONTROL = 82, SHIFT = 81, K = 55 }
local heldKeys = {}
local capturingKeybind = false
Keyboard = {
    IsAvailable = function() return true end,
    IsBlocked = function() return false end,
}
PersistentDB = {
    GetString = function() return nil end,
    GetStructuredData = function(_, key)
        if key == "markerKeybind" and storedMarkingKeybind ~= nil then
            return { table.unpack(storedMarkingKeybind) }
        end
    end,
    SetStructuredData = function(_, key, value)
        if key == "markerKeybind" then
            storedMarkingKeybind = { table.unpack(value) }
        end
        return true
    end,
    GetInt = function(_, key)
        if key == "markerFontSize" then return 19 end
        if key == "markerOutlineThicknessTenths" then return 35 end
        return nil
    end,
    GetBool = function(_, key)
        if key == "markerIgnoreDepth" then return true end
        return storedRendering[key]
    end,
    SetBool = function(_, key, value)
        if key == "markerHoverPreview" then storedHoverPreview = value end
        if key == "markerFill" or key == "markerOutlineCornersOnly" then
            storedRendering[key] = value
        end
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
    Sprite = {
        RS3_ICON_ACCORDION_0 = 30205,
        RS3_ICON_ACCORDION_1 = 30206,
        RS3_ICON_ACCORDION_2 = 30207,
        RS3_ICON_ACCORDION_3 = 30208,
        RS3_ICON_ACCORDION_4 = 30209,
        RS3_ICON_ACCORDION_5 = 30210,
    },
}
ScreenConvert = {
    CoordFineToScreen = function() return { x = 100, y = 100 } end,
}

ui = {
    Hook = { ONRESIZE = 1, ONMOUSEOVER = 2, ONMOUSELEAVE = 3, ONCLICK = 4 },
    AlignMode = {
        CENTRE = 1,
    },
    TextDataConfig = {
        new = function() return {} end,
    },
    Rectangle = {
        new = function(parent)
            local rectangle = {
                SetPos = function() end,
                SetSize = function() end,
            }
            parent.swatch = rectangle
            return rectangle
        end,
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
local promptSwatches
local promptCheckboxEntries
local promptCheckboxOptions
local settingsCallbacks = {}
local contentCallbacks = {}
local drawCallbacks = {}
local function runDrawFrame()
    local callbacks = {}
    for _, callback in pairs(drawCallbacks) do
        callbacks[#callbacks + 1] = callback
    end
    for _, callback in ipairs(callbacks) do callback() end
end

local function presentContent(parent)
    contentCallbacks.tilemarkers_content({ component = parent })
    -- Native presentation clears child components after dispatching the event.
    parent.children = {}
    runDrawFrame()
end
Event = {
    SettingsLayerReady = {
        Subscribe = function(id, callback) settingsCallbacks[id] = callback end,
        Unsubscribe = function(id) settingsCallbacks[id] = nil end,
    },
    ContentLayerReady = {
        Subscribe = function(id, callback) contentCallbacks[id] = callback end,
        Unsubscribe = function(id) contentCallbacks[id] = nil end,
    },
    Draw = {
        Subscribe = function(id, callback) drawCallbacks[id] = callback end,
        Unsubscribe = function(id) drawCallbacks[id] = nil end,
    },
}
local prettyui = {
    KeybindField = {
        IsCapturing = function() return capturingKeybind end,
        IsDown = function(value)
            if capturingKeybind or #value == 0 then return false end
            for _, key in ipairs(value) do
                if not heldKeys[key] then return false end
            end
            return true
        end,
    },
    Window = {
        new = function(_, options)
            promptWindowOptions = options
            local window = { root = {} }
            promptButtons = {}
            promptButtonOptions = {}
            promptTexts = {}
            promptSwatches = {}
            function window:AddText(value)
                local options = type(value) == "table"
                    and value or { text = tostring(value or "") }
                promptTexts[#promptTexts + 1] = options
            end
            function window:AddTextField(fieldOptions)
                assert(fieldOptions.maxLength <= 9999, "native input capacity exceeded")
                local field = {
                    value = (fieldOptions.text or ""):sub(1, fieldOptions.maxLength),
                    options = fieldOptions,
                }
                function field:GetText() return self.value end
                promptInput = field
                return field
            end
            function window:AddColourPicker(pickerOptions)
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
                promptCheckboxEntries = entries
                promptCheckboxOptions = checkboxOptions
                return {}
            end
            function window:AddSimpleButton(content, action, buttonOptions)
                local button = { root = {}, action = action }
                promptSwatches[#promptSwatches + 1] = button
                return button
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
    Sync = function(settings)
        for _, tile in ipairs(settings) do submitted[#submitted + 1] = tile end
        return true
    end,
}

package.loaded["src/ui"] = nil
local UI = require("src/ui")
UI:init({}, prettyui, draw)
expect(UI:isHoverPreviewEnabled(), true, "hover preview defaults on")
UI.canvas = {
    xyGlobal = { x = 0, y = 0 },
    Clear = function() label = nil end,
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
        return { level = 0, position = { x = 10 * 512 + 256, z = 10 * 512 + 256 } }
    end,
}

local function render(tiles, hover)
    local ready = UI:syncMarkers(tiles, hover, 30 * 512)
    UI:drawLabels(coord:ToCoordFine(true).position, coord.level)
    return ready
end

expect(render({ [coord] = {
    text = "Global label",
} }), true, "tile draws")
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
render({
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
render({ [coord] = {} }, emptyHover)
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
render({
    [coord] = { outlineColour = 0x00FFFFFF },
    [eastCoord] = { outlineColour = 0xFF00FFFF },
}, nil)
expect(#submitted, 2, "neighbouring tiles are both submitted to PrettyUI")

render({ [coord] = { text = "Retained label" } })
local playerFine = coord:ToCoordFine(true)
local originalProjection = ScreenConvert.CoordFineToScreen
ScreenConvert.CoordFineToScreen = function() return { x = 150, y = 80 } end
UI:drawLabels(playerFine.position, playerFine.level)
expect(label.x, 50, "camera movement repositions a retained label without marker reconciliation")
UI.canvas.xyGlobal = { x = 25, y = 15 }
UI:drawLabels(playerFine.position, playerFine.level)
expect(label.x + UI.canvas.xyGlobal.x + 100, 150,
    "label stays horizontally aligned when its canvas origin changes")
expect(label.y + UI.canvas.xyGlobal.y + 18, 80,
    "label stays vertically aligned when its canvas origin changes")
UI.canvas.xyGlobal = { x = 0, y = 0 }
ScreenConvert.CoordFineToScreen = originalProjection
playerFine.position.x = playerFine.position.x + 30 * 512 + 256
UI:drawLabels(playerFine.position, playerFine.level)
expect(label.text, "Retained label", "label remains at the native draw-distance boundary")
playerFine.position.x = playerFine.position.x + 1
UI:drawLabels(playerFine.position, playerFine.level)
expect(label, nil, "label disappears beyond native draw distance despite retained marker")
playerFine = coord:ToCoordFine(true)
playerFine.level = 1
UI:drawLabels(playerFine.position, playerFine.level)
expect(label, nil, "labels do not leak onto another floor")
UI:drawLabels(coord:ToCoordFine(true).position, coord.level)
render({})
expect(label, nil, "removing the last labelled marker clears its canvas text")

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
UI.globalStyle.fill = true
UI.globalStyle.outlineCornersOnly = true
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
expect(UI:isPromptOpen(), true, "open colour prompt is tracked")
expect(promptInput.value, "Existing label", "customization prepopulates the tile label")
expect(promptColourPicker.value, 0x11223380, "colour prompt starts from tile colour")
expect(promptColourPickerOptions.alphaSlider, true, "colour prompt exposes opacity")
expect(promptCheckboxEntries[1].selected, false, "explicit fill off overrides enabled global")
expect(promptCheckboxEntries[2].selected, false, "explicit corners off overrides enabled global")
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

expect(UI:promptForCustomization("", 0x445566FF, nil, nil, {
    preview = function(_, _, fill, corners)
        previewedFill, previewedOutlineCornersOnly = fill, corners
    end,
    confirm = function(_, _, fill, corners)
        acceptedFill, acceptedOutlineCornersOnly = fill, corners
    end,
}), true, "inherited customization opens")
expect(promptCheckboxEntries[1].selected, true, "inherited fill displays enabled global")
expect(promptCheckboxEntries[2].selected, true, "inherited corners display enabled global")
promptInput.value = "Label-only change"
promptInput.options.onChange()
promptColourPicker:SetValue(0x445566FF)
expect(previewedFill, nil, "label and colour preview preserve fill inheritance")
expect(previewedOutlineCornersOnly, nil, "label and colour preview preserve corner inheritance")
promptButtons.Confirm()
expect(acceptedFill, nil, "untouched fill checkbox keeps inheritance on confirm")
expect(acceptedOutlineCornersOnly, nil, "untouched corners checkbox keeps inheritance on confirm")

expect(UI:promptForCustomization("", 0x445566FF, nil, nil, {
    preview = function(_, _, fill, corners)
        previewedFill, previewedOutlineCornersOnly = fill, corners
    end,
    confirm = function(_, _, fill, corners)
        acceptedFill, acceptedOutlineCornersOnly = fill, corners
    end,
}), true, "inherited fill can be overridden")
promptCheckboxOptions.onChange(nil, nil, "render_fill", false)
expect(previewedFill, false, "first fill click previews explicit disabled fill")
expect(previewedOutlineCornersOnly, nil, "fill click leaves corners inherited")
promptCheckboxOptions.onChange(nil, nil, "render_fill", true)
promptButtons.Confirm()
expect(acceptedFill, true, "toggling fill back still creates an explicit override")
expect(acceptedOutlineCornersOnly, nil, "confirm leaves untouched corners inherited")
UI.globalStyle.fill = false
UI.globalStyle.outlineCornersOnly = false
submitted = {}
render({ [coord] = { fill = acceptedFill, outlineCornersOnly = acceptedOutlineCornersOnly } })
expect(submitted[1].fill, true, "interacted fill no longer follows global changes")
expect(submitted[1].outlineCornersOnly, false, "untouched corners still follow global changes")

expect(UI:promptForCustomization("", 0x445566FF, nil, nil, {
    confirm = function(_, _, fill, corners)
        acceptedFill, acceptedOutlineCornersOnly = fill, corners
    end,
}), true, "inherited corners can be overridden")
expect(promptCheckboxEntries[1].selected, false, "inherited fill displays disabled global")
expect(promptCheckboxEntries[2].selected, false, "inherited corners display disabled global")
promptCheckboxOptions.onChange(nil, nil, "outline_corners_only", true)
promptCheckboxOptions.onChange(nil, nil, "outline_corners_only", false)
promptButtons.Confirm()
expect(acceptedFill, nil, "corner interaction leaves fill inherited")
expect(acceptedOutlineCornersOnly, false, "toggling corners back preserves explicit false override")

UI:rememberColour(0xAABBCCDD)
local cancelledCustomization = false
local unexpectedlyConfirmed = false
expect(UI:promptForCustomization("Keep me", 0x010203FF, true, true, {
    confirm = function()
        unexpectedlyConfirmed = true
    end,
    preview = function(_, colour) previewedColour = colour end,
    cancel = function()
        cancelledCustomization = true
    end,
}), true, "second colour prompt opens")
expect(#promptSwatches, 2, "recent colours render as separate swatches")
expect(promptSwatches[1].root.swatch.rgba, 0xAABBCCDD, "newest swatch shows its exact colour")
promptSwatches[1].action()
expect(promptColourPicker.value, 0xAABBCCDD, "newest swatch selects its colour and opacity")
expect(previewedColour, 0xAABBCCDD, "swatch selection previews immediately")
promptSwatches[2].action()
expect(promptColourPicker.value, 0x445566FF, "second swatch selects its own colour")
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
local exportToken = string.rep("A", 9999)
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
        return true, exportToken
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
expect(UI.presetExportInput:GetText(), exportToken, "maximum-length export is not truncated")
promptButtons.Close()

exportToken = exportToken .. "A"
expect(UI:promptForPresetExport("preset_1", "Large"), true, "oversized export opens a warning")
expect(UI.presetExportInput, nil, "oversized export never exposes a truncated token")
assert(promptTexts[1].text:find("10000", 1, true), "warning reports required character count")
assert(promptTexts[1].text:find("9999", 1, true), "warning reports sharing capacity")
promptButtons.Close()
expect(UI:isPromptOpen(), false, "oversized export warning closes")

local editOverlay
local makeControl
makeControl = function()
    local control = {
        content = { content = "" },
        addedControls = {},
        subscriptions = {},
        addedComponents = {},
    }
    control.root = control

    local function addControl(self, options)
        local child = makeControl()
        child.options = options
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
        child.height = options.height
        return child
    end
    control.AddSimpleButton = addControl
    control.AddSlider = addControl
    control.AddSprite = function(self, sprite, options)
        local child = addControl(self, options)
        child.sprite = sprite
        return child
    end
    control.SetSprite = function(self, sprite) self.sprite = sprite end
    control.AddSpriteButton = function(self, sprite, action, options)
        self.addedControls[#self.addedControls + 1] = "sprite:" .. sprite
        local child = addControl(self)
        child.sprite = sprite
        child.action = action
        child.options = options
        return child
    end
    control.AddText = function(self, options)
        self.addedControls[#self.addedControls + 1] = "text"
        local child = addControl(self)
        child.options = options
        return child
    end
    control.AddTextField = addControl
    control.AddKeybindField = function(self, options)
        self.keybindOptions = options
        return addControl(self, options)
    end
    control.Close = function() end
    control.Select = function() end
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
    control.Subscribe = function(self, hook, callback) self.subscriptions[hook] = callback end
    control.SetSize = function(self, width, height)
        self.width, self.height = width, height
    end
    control.RefreshRowBackgrounds = function(self)
        self.rowBackgroundsRefreshed = true
    end
    return control
end

UI.prettyui = {
    KeybindField = prettyui.KeybindField,
    SimpleView = {
        new = function(parent)
            local view = makeControl()
            view.contentWidth = parent.width
            function view:Refresh()
                self.contentWidth = parent.width
            end
            parent.children = parent.children or {}
            parent.children[#parent.children + 1] = view.root
            return view
        end,
    },
    Panel = {
        new = function()
            editOverlay = makeControl()
            return editOverlay
        end,
    },
}
local mountedPreset = { id = "preset_1", name = "My preset" }
local mountedPresetActive = true
UI.presetHandlers = {
    list = function() return { mountedPreset } end,
    isActive = function() return mountedPresetActive end,
    setActive = function(_, value) mountedPresetActive = value; return true end,
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
local contentParent = { width = 640, height = 480 }
presentContent(contentParent)
expect(contentParent.children[1], UI.contentView.root,
    "preset content survives the native post-event clear")
local initialContent = UI.contentView
expect(UI.settingsView, nil, "presets can open before marker settings")
settingsCallbacks.tilemarkers_settings({ component = { width = 640, height = 480 } })
expect(UI.contentView, initialContent, "opening settings leaves preset content mounted")
local markerOptions = UI.settingsView.addedComponents[1]
markerOptions.options.onChange(nil, nil, "hover_preview", false)
expect(UI:isHoverPreviewEnabled(), false, "hover preview toggle updates runtime state")
expect(storedHoverPreview, false, "hover preview toggle persists")

local keybindOptions = UI.settingsView.keybindOptions
heldKeys = { [GameKey.CONTROL] = true, [GameKey.SHIFT] = true }
expect(UI:isMarkingKeybindDown(), true, "unset override uses Ctrl+Shift")
keybindOptions.onChange(nil, { GameKey.K })
expect(UI:isMarkingKeybindDown(), false, "override replaces the default chord")
heldKeys = { [GameKey.K] = true }
expect(UI:isMarkingKeybindDown(), true, "single-key override activates marking")
local keybindLibrary = UI.prettyui
UI:init(UI.presetHandlers, keybindLibrary, draw)
expect(UI:isMarkingKeybindDown(), true, "single-key override survives reload")
keybindOptions.onChange(nil, { GameKey.CONTROL, GameKey.K })
expect(UI:isMarkingKeybindDown(), false, "two-key override requires both keys")
heldKeys[GameKey.CONTROL] = true
UI:init(UI.presetHandlers, keybindLibrary, draw)
expect(UI:isMarkingKeybindDown(), true, "two-key override survives reload")
capturingKeybind = true
expect(UI:isMarkingKeybindDown(), false, "capture suppresses the active override")
capturingKeybind = false
keybindOptions.onChange(nil, {})
expect(UI:isMarkingKeybindDown(), false, "clear discards the custom chord")
heldKeys = { [GameKey.CONTROL] = true, [GameKey.SHIFT] = true }
expect(UI:isMarkingKeybindDown(), true, "clearing restores default marking")
UI:init(UI.presetHandlers, keybindLibrary, draw)
expect(UI:isMarkingKeybindDown(), true, "cleared override keeps fallback after reload")
keybindOptions.onChange(nil, { GameKey.K })
keybindOptions.onChange(nil, keybindOptions.defaultValue)
UI:init(UI.presetHandlers, keybindLibrary, draw)
expect(UI:isMarkingKeybindDown(), true, "context reset restores persisted default")
heldKeys = { [GameKey.K] = true }
expect(UI:isMarkingKeybindDown(), false, "reset removes the custom override")

local inheritedMarker = UI:getStyle()
local renderingOptions = markerOptions.options
renderingOptions.onChange(nil, nil, "fill", true)
renderingOptions.onChange(nil, nil, "outlineCornersOnly", true)
submitted = {}
render({ [coord] = inheritedMarker })
expect(submitted[1].fill, true, "placed marker follows global fill change")
expect(submitted[1].outlineCornersOnly, true, "placed marker follows global corner change")
render({ [coord] = { fill = false, outlineCornersOnly = false } })
expect(submitted[2].fill, false, "explicit fill off overrides enabled global")
expect(submitted[2].outlineCornersOnly, false, "explicit corners off overrides enabled global")
submitted = {}
render({ [coord] = inheritedMarker }, sameTileHover)
expect(submitted[1].fill, true, "marked hover preserves inherited fill")
expect(submitted[1].outlineCornersOnly, true, "marked hover preserves inherited corners")
renderingOptions.onChange(nil, nil, "fill", false)
renderingOptions.onChange(nil, nil, "outlineCornersOnly", false)
submitted = {}
render({ [coord] = inheritedMarker })
expect(submitted[1].fill, false, "inherited fill updates without replacing marker")
expect(submitted[1].outlineCornersOnly, false, "inherited corners update without replacing marker")
render({ [coord] = { fill = true, outlineCornersOnly = true } })
expect(submitted[2].fill, true, "explicit fill on overrides disabled global")
expect(submitted[2].outlineCornersOnly, true, "explicit corners on override disabled global")
local mountedPrettyUI = UI.prettyui
renderingOptions.onChange(nil, nil, "fill", true)
UI:init(UI.presetHandlers, prettyui, draw)
submitted = {}
render({ [coord] = inheritedMarker })
expect(submitted[1].fill, true, "enabled global fill survives settings reload")
expect(submitted[1].outlineCornersOnly, false, "disabled global corners survive settings reload")
renderingOptions.onChange(nil, nil, "outlineCornersOnly", true)
renderingOptions.onChange(nil, nil, "fill", false)
UI:init(UI.presetHandlers, prettyui, draw)
submitted = {}
render({ [coord] = inheritedMarker })
expect(submitted[1].fill, false, "disabled global fill survives settings reload")
expect(submitted[1].outlineCornersOnly, true, "enabled global corners survive settings reload")
UI.prettyui = mountedPrettyUI
local function presetControl(sprite)
    for _, control in ipairs(UI.presetPanelsByID.preset_1.addedComponents) do
        if control.sprite == sprite then return control end
    end
end
UI.contentView.scrollY = 120
presetControl("EYE").action()
expect(
    UI.contentView.restoredScrollY,
    120,
    "preset toggle restores the previous scroll position")
UI:rebuildPresetPanels("preset_1")
expect(
    UI.contentView.scrolledToChild,
    UI.presetPanelsByID.preset_1,
    "new preset focus scrolls its panel into view")

for _, sprite in ipairs({ "PENCIL", "SETTINGS", "EXPORT", "TRASH" }) do
    expect(presetControl(sprite), nil, "preset actions start collapsed: " .. sprite)
end
local chevron = presetControl(id.Sprite.RS3_ICON_ACCORDION_0)
chevron.subscriptions[ui.Hook.ONMOUSEOVER]()
expect(chevron.sprite, id.Sprite.RS3_ICON_ACCORDION_1, "hover highlights the preset chevron")
chevron.subscriptions[ui.Hook.ONMOUSELEAVE]()
expect(chevron.sprite, id.Sprite.RS3_ICON_ACCORDION_0, "leaving restores the preset chevron")
chevron.subscriptions[ui.Hook.ONCLICK]()
local expandedPresetHeight = UI.presetPanelsByID.preset_1.height
presetControl(id.Sprite.RS3_ICON_ACCORDION_3).subscriptions[ui.Hook.ONCLICK]()
local collapsedPresetHeight = UI.presetPanelsByID.preset_1.height
expect(collapsedPresetHeight < expandedPresetHeight, true, "collapse removes the action row height")
for _, sprite in ipairs({ "PENCIL", "SETTINGS", "EXPORT", "TRASH" }) do
    expect(presetControl(sprite), nil, "collapsed actions cannot receive clicks: " .. sprite)
end
presetControl("HIDE").action()
expect(mountedPresetActive, true, "a collapsed preset can still be enabled")
expect(UI.presetPanelsByID.preset_1.height, collapsedPresetHeight,
    "activation does not expand the preset")
presentContent({ width = 480, height = 240 })
expect(UI.presetPanelsByID.preset_1.height, collapsedPresetHeight,
    "reopening content preserves the preset collapse state")
presetControl(id.Sprite.RS3_ICON_ACCORDION_0).subscriptions[ui.Hook.ONCLICK]()
expect(UI.presetPanelsByID.preset_1.height, expandedPresetHeight, "expansion restores the action row")
for _, sprite in ipairs({ "PENCIL", "SETTINGS", "EXPORT", "TRASH" }) do
    expect(presetControl(sprite) ~= nil, true, "expanded actions become available: " .. sprite)
end
presentContent({ width = 480, height = 240 })
expect(UI.presetPanelsByID.preset_1.height, expandedPresetHeight,
    "reopening content preserves an explicitly expanded preset")

local responsiveParent = { width = 640, height = 240 }
presentContent(responsiveParent)
UI.contentView.scrollY = 50
local wideView = UI.contentView
local wideCardHeight = UI.presetPanelsByID.preset_1.height
responsiveParent.width = 180
wideView.subscriptions[ui.Hook.ONRESIZE]()
expect(wideView.destroyed, true, "crossing into compact layout releases the old view")
expect(UI.contentView.scrollY, 50, "compact transition preserves the scroll position")
expect(mountedPresetActive, true, "compact transition preserves preset activation")
expect(UI.collapsedPresets.preset_1, false, "compact transition preserves expansion")
expect(UI.presetPanelsByID.preset_1.height < wideCardHeight, true,
    "compact cards reclaim vertical space")
for _, sprite in ipairs({ "PENCIL", "SETTINGS", "EXPORT", "TRASH" }) do
    expect(presetControl(sprite) ~= nil, true, "compact actions remain available: " .. sprite)
end
local compactView = UI.contentView
responsiveParent.width = 200
compactView.subscriptions[ui.Hook.ONRESIZE]()
expect(UI.contentView, compactView, "resizing within compact mode does not recreate controls")
presetControl(id.Sprite.RS3_ICON_ACCORDION_3).subscriptions[ui.Hook.ONCLICK]()
presetControl("EYE").action()
expect(mountedPresetActive, false, "compact eye control toggles the preset")
responsiveParent.width = 640
compactView.subscriptions[ui.Hook.ONRESIZE]()
expect(compactView.destroyed, true, "expanding beyond compact mode releases the old view")
expect(UI.collapsedPresets.preset_1, true, "wide transition preserves collapse")
expect(mountedPresetActive, false, "wide transition preserves the disabled preset")
expect(presetControl("PENCIL"), nil, "wide transition does not expose collapsed actions")
presetControl(id.Sprite.RS3_ICON_ACCORDION_0).subscriptions[ui.Hook.ONCLICK]()
expect(UI.presetPanelsByID.preset_1.height, wideCardHeight,
    "expanding restores normal card spacing in a wide panel")

presetControl("SETTINGS").action()
expect(editOverlay ~= nil, true, "edit action mounts a PrettyUI panel overlay")
editOverlay.addedComponents[4].action()
expect(editOverlay.destroyed, true, "cancel destroys the edit overlay")
expect(UI.presetEditOverlay, nil, "cancel exits UI edit mode")

UI.presetHandlers.saveEdit = function()
    return false
end
presetControl("SETTINGS").action()
local failedSaveOverlay = editOverlay
failedSaveOverlay.addedComponents[3].action()
expect(
    UI.presetEditOverlay,
    failedSaveOverlay,
    "failed save keeps preset edit mode open")
local previousSettings = UI.settingsView
local previousCanvas = UI.canvas
local previousContent = UI.contentView
settingsCallbacks.tilemarkers_settings({ component = { width = 640, height = 480 } })
expect(previousSettings.destroyed, true, "reopening settings releases the previous view")
expect(UI.contentView, previousContent, "reopening settings keeps preset content")
expect(previousContent.destroyed, nil, "settings remount does not destroy preset content")
local remountedOptions = UI.settingsView.addedComponents[1].entries
expect(remountedOptions[3].selected, false, "reopening settings preserves fill changes")
expect(remountedOptions[4].selected, true, "reopening settings preserves corner changes")
expect(UI.canvas, previousCanvas, "reopening settings keeps the marker canvas")
expect(UI.presetEditOverlay, failedSaveOverlay, "reopening settings keeps active preset editing")
local remountedSettings = UI.settingsView
presentContent({ width = 480, height = 240 })
expect(previousContent.destroyed, true, "reopening content releases the previous view")
expect(UI.settingsView, remountedSettings, "reopening content keeps marker settings")
expect(remountedSettings.destroyed, nil, "content remount does not destroy marker settings")
expect(UI.canvas, previousCanvas, "reopening content keeps the marker canvas")
expect(UI.presetEditOverlay, failedSaveOverlay, "reopening content keeps active preset editing")
failedSaveOverlay.addedComponents[4].action()


-- Cancelling during logout must not inspect native input contents.
UI.colourPromptLabelInput = {
    GetText = function() error("read after interface unload") end,
}
local cancelCount = 0
UI.colourPromptActions = { cancel = function() cancelCount = cancelCount + 1 end }
UI:finishColourPrompt(false)
expect(cancelCount, 1, "logout cancellation preserves the cancel callback")

local destroyedPrompts = {}
local function retainedPrompt(name)
    return { root = {}, Destroy = function() destroyedPrompts[name] = true end }
end
UI.presetCreateWindow = nil
UI.presetImportWindow = retainedPrompt("import")
UI.presetRenameWindow = nil
UI.presetExportWindow = retainedPrompt("export")
UI.presetDeleteWindow = retainedPrompt("delete")
UI.canvas = { Destroy = function() error("destroy after interface unload") end }
id.Component = { TOPLEVEL_V2__GAME_AREA = 1, TOPLEVEL_V2__PLUGIN_BUILD_LAYER_BOTTOM = 2 }
ui.Interfaces = { GetComponent = function() return nil end }
UI:destroy()
expect(destroyedPrompts.import, true, "missing create prompt does not skip import cleanup")
expect(destroyedPrompts.export, true, "missing rename prompt does not skip export cleanup")
expect(destroyedPrompts.delete, true, "all retained prompts are cleaned up")
expect(UI.gameArea, nil, "logout forgets the old game area")
expect(UI.canvas, nil, "logout discards the dead native canvas")

local retainedSettings = UI.settingsView
local retainedContent = UI.contentView
expect(UI:ensureMounted(), false, "world rendering waits for the game area")
expect(UI.settingsView, retainedSettings, "missing game area leaves native settings intact")
expect(UI.contentView, retainedContent, "missing game area leaves native content intact")
expect(UI:startPresetEdit("preset_1", "My preset"), false, "tile editing requires the game area")
UI:shutdown()
expect(retainedSettings.destroyed, true, "shutdown destroys native settings")
expect(UI.settingsView, nil, "shutdown forgets the settings view")
expect(retainedContent.destroyed, true, "shutdown destroys native content")
expect(UI.contentView, nil, "shutdown forgets the content view")
expect(next(settingsCallbacks), nil, "shutdown unsubscribes settings mounting")
expect(next(contentCallbacks), nil, "shutdown unsubscribes content mounting")
expect(next(drawCallbacks), nil, "shutdown leaves no pending content mount")

-- Only the latest presentation may mount when several arrive before a draw.
UI:init(UI.presetHandlers, mountedPrettyUI, draw)
local abandonedParent = { width = 640, height = 480 }
local latestParent = { width = 480, height = 240 }
contentCallbacks.tilemarkers_content({ component = abandonedParent })
abandonedParent.children = {}
contentCallbacks.tilemarkers_content({ component = latestParent })
latestParent.children = {}
runDrawFrame()
expect(abandonedParent.children[1], nil, "superseded content layer stays empty")
expect(latestParent.children[1], UI.contentView.root, "latest content layer receives presets")
local mountedContent = UI.contentView
runDrawFrame()
expect(UI.contentView, mountedContent, "later draws do not rebuild preset content")

-- Logout and shutdown must cancel a presentation before its first draw.
local cancelledParent = { width = 640, height = 480 }
contentCallbacks.tilemarkers_content({ component = cancelledParent })
cancelledParent.children = {}
UI:destroyContent()
runDrawFrame()
expect(cancelledParent.children[1], nil, "content teardown cancels a pending mount")
expect(UI.contentView, nil, "content teardown does not resurrect a view")
contentCallbacks.tilemarkers_content({ component = cancelledParent })
cancelledParent.children = {}
UI:shutdown()
runDrawFrame()
expect(cancelledParent.children[1], nil, "shutdown cancels a pending mount")
expect(UI.contentView, nil, "shutdown does not resurrect a view")

print("test_global_config: ok")
