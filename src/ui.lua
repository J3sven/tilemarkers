local Styles = require("src/styles")
local Draw = require("src/draw")

local UI = {}

local OUTLINE_COLOUR_STORAGE_KEY = "markerOutlineColour"
local RECENT_COLOURS_STORAGE_KEY = "recentMarkerColours"
local MAX_RECENT_COLOURS = 5
local OUTLINE_THICKNESS_STORAGE_KEY = "markerOutlineThicknessTenths"
local FONT_SIZE_STORAGE_KEY = "markerFontSize"
local IGNORE_DEPTH_STORAGE_KEY = "markerIgnoreDepth"
local HOVER_PREVIEW_STORAGE_KEY = "markerHoverPreview"
local FILL_STORAGE_KEY = "markerFill"
local OUTLINE_CORNERS_STORAGE_KEY = "markerOutlineCornersOnly"
local EMPTY_HOVER_STYLE = {
    outlineColour = 0xFFFFFF90,
    fillColour = 0xFFFFFF38,
    fill = true,
}
local HOVER_LIGHTEN_NUMERATOR = 3
local HOVER_LIGHTEN_DENOMINATOR = 10

local function lightenColour(colour)
    local function lighten(channel)
        return channel
            + ((0xFF - channel) * HOVER_LIGHTEN_NUMERATOR
                + HOVER_LIGHTEN_DENOMINATOR // 2)
                // HOVER_LIGHTEN_DENOMINATOR
    end

    local red = lighten((colour >> 24) & 0xFF)
    local green = lighten((colour >> 16) & 0xFF)
    local blue = lighten((colour >> 8) & 0xFF)
    return (red << 24)
        | (green << 16)
        | (blue << 8)
        | (colour & 0xFF)
end

local function labelColour(outlineColour)
    return lightenColour(lightenColour(outlineColour))
end

local function markedHoverStyle(metadata, defaults)
    local style = Styles.normalize(metadata, defaults)
    style.outlineColour = lightenColour(style.outlineColour)
    style.fillColour = lightenColour(style.fillColour)
    return style
end

local function parseRecentColours(value)
    local colours = {}
    local seen = {}
    for hexadecimal in tostring(value or ""):gmatch("(%x%x%x%x%x%x%x%x)") do
        local colour = tonumber(hexadecimal, 16)
        if colour ~= nil and not seen[colour] then
            colours[#colours + 1] = colour
            seen[colour] = true
            if #colours == MAX_RECENT_COLOURS then break end
        end
    end
    return colours
end

local function encodeRecentColours(colours)
    local encoded = {}
    for _, colour in ipairs(colours) do
        encoded[#encoded + 1] = Styles.encodeColour(colour)
    end
    return table.concat(encoded, ",")
end



local WINDOW_WIDTH = 416
local WINDOW_HEIGHT = 482
local CONTROL_GAP = 8
local DEFAULT_LABEL_SIZE = 19
local LABEL_SIZES = {
    [15] = true,
    [19] = true,
    [17] = true,
}
local LABEL_SIZE_BY_ENTRY_ID = {
    [1] = 15,
    [2] = 17,
    [3] = 19,
}
local LABEL_SIZE_ENTRY_ID = {
    [15] = 1,
    [17] = 2,
    [19] = 3,
}
local LABEL_SIZE_SORTED_POSITION = {
    [1] = 3,
    [2] = 2,
    [3] = 1,
}

local PAGE_BY_NAME = {
    markers = 1,
    presets = 2,
}

local fontCache = {}
local textConfigCache = {}

local function fontByName(name)
    local available, font = pcall(function() return id.Font[name] end)
    return available and font or nil
end

local function labelFont(size)
    if fontCache[size] ~= nil then return fontCache[size] end

    local function find(candidate)
        return fontByName("MUSEO_SANS_" .. tostring(candidate) .. "PT_REGULAR")
            or fontByName("MUSEO_SANS_" .. tostring(candidate) .. "PT")
    end

    local font = find(size)
    if font == nil then
        for offset = 1, 32 do
            local lower = size - offset
            local upper = size + offset
            if lower >= 8 then font = find(lower) end
            if font == nil and upper <= 40 then font = find(upper) end
            if font ~= nil then break end
        end
    end
    fontCache[size] = font or id.Font.MUSEO_SANS_11PT_REGULAR
    return fontCache[size]
end

local function labelTextConfig(style)
    local key = string.format("%08X:%d", style.outlineColour, style.fontSize)
    local cached = textConfigCache[key]
    if cached ~= nil then return cached end

    local config = ui.TextDataConfig.new()
    config.font = labelFont(style.fontSize)
    config.alignHorizontal = ui.AlignMode.CENTRE
    config.alignVertical = ui.AlignMode.CENTRE
    config.rgba = style.outlineColour
    config.shadowRGBA = 0x000000FF
    config.isShadowed = true
    textConfigCache[key] = config
    return config
end

local function round(value)
    return math.floor(value + 0.5)
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function normalizeLabelSize(value)
    value = math.floor(tonumber(value) or DEFAULT_LABEL_SIZE)
    return LABEL_SIZES[value] and value or DEFAULT_LABEL_SIZE
end


local function gridPosition(coord)
    local available, level, x, z = pcall(function()
        return coord.level, coord.x, coord.z
    end)
    if not available or level == nil or x == nil or z == nil then return nil end
    return {
        level = level,
        x = x,
        z = z,
        key = string.format("%d:%d:%d", level, x, z),
    }
end

function UI:init(presetHandlers, prettyUILibrary, drawLibrary)
    self.presetHandlers = presetHandlers
    self.prettyui = assert(
        prettyUILibrary,
        "Tile Marker requires the prettyui dependency to be enabled first")
    self.renderer = drawLibrary or Draw
    self.currentPage = "markers"
    self.recentColours = parseRecentColours(
        PersistentDB:GetString(RECENT_COLOURS_STORAGE_KEY))
    self.ignoreDepth = PersistentDB:GetBool(IGNORE_DEPTH_STORAGE_KEY) == true
    self.hoverPreviewEnabled =
        PersistentDB:GetBool(HOVER_PREVIEW_STORAGE_KEY) ~= false
    self.globalStyle = {
        fill = PersistentDB:GetBool(FILL_STORAGE_KEY) == true,
        outlineCornersOnly = PersistentDB:GetBool(OUTLINE_CORNERS_STORAGE_KEY) == true,
    }
    local storedLabelSize = PersistentDB:GetInt(FONT_SIZE_STORAGE_KEY)
    self.labelSize = normalizeLabelSize(storedLabelSize)
    self.outlineThickness = clamp(
        (PersistentDB:GetInt(OUTLINE_THICKNESS_STORAGE_KEY) or 20) / 10,
        0.0,
        10.0)
    self.currentStyle = Styles.fromColour(
        PersistentDB:GetInt(OUTLINE_COLOUR_STORAGE_KEY))
    self.ribbonRegistration = self.prettyui.RibbonBar.Register({
        id = "tilemarkers",
        object = config.Obj.ROOFTILE,
        tooltip = "Open Tile Markers",
        onClick = function(_, active) self:setPanelOpen(active) end,
    })
end

function UI:reset()
    if self.presetEditOverlay ~= nil
        and self.presetHandlers ~= nil
        and self.presetHandlers.cancelEdit ~= nil then
        self.presetHandlers.cancelEdit()
    end
    self.canvas = nil
    self.window = nil
    self.tabs = nil
    self.clearPromptWindow = nil
    self.clearPromptCallback = nil
    self.colourPromptWindow = nil
    self.colourPromptLabelInput = nil
    self.colourPromptPicker = nil
    self.colourPromptColour = nil
    self.colourPromptFill = nil
    self.colourPromptOutlineCornersOnly = nil
    self.colourPromptActions = nil
    self.colourPicker = nil
    self.thicknessText = nil
    self.thicknessSlider = nil
    self.labelSizeCombo = nil
    self.presetPage = nil
    self.presetPanels = {}
    self.presetPanelsByID = {}
    self.presetEditOverlay = nil
    self.presetEditStatus = nil
    self.presetCreateWindow = nil
    self.presetCreateInput = nil
    self.presetCreateVisible = nil
    self.presetImportWindow = nil
    self.presetImportInput = nil
    self.presetRenameWindow = nil
    self.presetRenameInput = nil
    self.presetRenameID = nil
    self.presetDeleteWindow = nil
    self.presetDeleteID = nil
    self.presetExportWindow = nil
    self.presetExportInput = nil
    self.gameArea = nil
end

function UI:destroy()
    if self.presetEditOverlay ~= nil then
        self.presetEditOverlay:Destroy()
    end
    self.presetEditOverlay = nil
    self.presetEditStatus = nil
    if self.clearPromptWindow ~= nil and self.clearPromptWindow.root ~= nil then
        self.clearPromptWindow:Destroy()
    end
    self.clearPromptWindow = nil
    self.clearPromptCallback = nil
    if self.colourPromptWindow ~= nil then
        self:finishColourPrompt(false)
    end
    for _, field in ipairs({
        "presetCreateWindow",
        "presetImportWindow",
        "presetRenameWindow",
        "presetExportWindow",
        "presetDeleteWindow",
    }) do
        local prompt = self[field]
        if prompt ~= nil and prompt.root ~= nil then prompt:Destroy() end
    end
    if self.window ~= nil then self.window:Destroy() end
    if self.canvas ~= nil and self.gameArea ~= nil
        and ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA) == self.gameArea then
        self.canvas:Destroy()
    end
    self:reset()
end

function UI:shutdown()
    self:destroy()
    if self.ribbonRegistration ~= nil then
        self.ribbonRegistration:Destroy()
        self.ribbonRegistration = nil
    end
end

function UI:clearPresetPanels()
    for _, panel in ipairs(self.presetPanels or {}) do
        panel:Destroy()
    end
    self.presetPanels = {}
    self.presetPanelsByID = {}
end

function UI:closePresetEditOverlay()
    local overlay = self.presetEditOverlay
    self.presetEditOverlay = nil
    self.presetEditStatus = nil
    if overlay ~= nil then overlay:Destroy() end
end

function UI:finishPresetEdit(save)
    if self.presetEditOverlay == nil then return false end
    local handler = save
        and self.presetHandlers.saveEdit
        or self.presetHandlers.cancelEdit
    local success, message = handler()
    if not success then
        if self.presetEditStatus ~= nil then
            self.presetEditStatus.content = message or "Could not finish preset editing."
        end
        return false
    end
    self:closePresetEditOverlay()
    self:rebuildPresetPanels()
    return true
end

function UI:startPresetEdit(presetID, presetName)
    if self.presetEditOverlay ~= nil or self:isPromptOpen() then return false end
    local success = self.presetHandlers.startEdit(presetID)
    if not success then return false end

    local width = 480
    local height = 116
    local x = clamp(
        math.floor((self.gameArea.width - width) / 2),
        0,
        math.max(0, self.gameArea.width - width))
    local overlay = self.prettyui.Panel.new(self.gameArea, {
        x = x,
        y = 18,
        width = width,
        height = height,
        backgroundAlpha = 0.78,
        popout = false,
        scrollable = false,
        layout = {
            startY = 8,
            paddingLeft = 14,
            paddingRight = 14,
            rowGap = 6,
        },
    })
    self.presetEditOverlay = overlay
    overlay:AddText({
        text = "Editing tilemarker preset: " .. tostring(presetName or "Preset"),
        height = 24,
        maxLines = 1,
        colour = 0xF2C66DFF,
    })
    self.presetEditStatus = overlay:AddText({
        text = "Add, remove or customize tile markers.",
        height = 24,
        maxLines = 1,
    })
    overlay:AddFancyButton("Save", function()
        self:finishPresetEdit(true)
    end, {
        width = 214,
        variant = "positive",
    })
    overlay:AddFancyButton("Cancel", function()
        self:finishPresetEdit(false)
    end, {
        inline = true,
        width = 214,
        variant = "negative",
    })
    if overlay.root ~= nil then overlay.root:MoveToFront() end
    self:setPanelOpen(false)
    return true
end

function UI:rebuildPresetPanels(focusPresetID)
    if self.presetPage == nil then return end
    local scrollY = self.presetPage.scrollY or 0
    self:clearPresetPanels()

    local presets = self.presetHandlers and self.presetHandlers.list() or {}
    if #presets == 0 then
        self.presetPanels[1] = self.presetPage:AddText({
            text = "No presets saved.",
            width = 344,
            height = 32,
            alignHorizontal = ui.AlignMode.CENTRE,
        })
        self.presetPage:SetScrollPosition(scrollY)
        return
    end

    for _, preset in ipairs(presets) do
        local presetID = preset.id
        local presetName = preset.name
        local active = self.presetHandlers.isActive(presetID)
        local panel = self.presetPage:AddPanel({
            width = 344,
            height = 96,
            popout = false,
            scrollable = false,
            layout = {
                startY = 10,
                paddingLeft = 14,
                paddingRight = 14,
                paddingBottom = 0,
                rowGap = 8,
            },
            rowBackgroundColours = {
                0x24211EFF,
                0x2E2825FF,
            },
            rowBackgroundEdgeToEdge = true,
        })
        self.presetPanels[#self.presetPanels + 1] = panel
        self.presetPanelsByID[presetID] = panel
        panel:AddSpriteButton("PENCIL", function()
            self:promptForPresetRename(presetID, presetName)
        end, {
            size = 24,
            tooltip = "Rename preset",
        })
        panel:AddText({
            text = presetName,
            inline = true,
            width = 260,
            height = 24,
            maxLines = 1,
        })
        panel:AddSpriteButton(active and "EYE" or "HIDE", function()
            local success = self.presetHandlers.setActive(presetID, not active)
            if success then self:rebuildPresetPanels() end
        end, {
            x = 202,
            marginTop = 12,
            size = 24,
            tooltip = active and "Disable preset" or "Enable preset",
        })
        panel:AddSpriteButton("SETTINGS", function()
            self:startPresetEdit(presetID, presetName)
        end, {
            inline = true,
            size = 24,
            tooltip = "Edit preset tiles",
        })
        panel:AddSpriteButton("EXPORT", function()
            self:promptForPresetExport(presetID, presetName)
        end, {
            inline = true,
            size = 24,
            tooltip = "Export preset",
        })
        panel:AddSpriteButton("TRASH", function()
            self:promptForPresetDelete(presetID, presetName)
        end, {
            inline = true,
            size = 24,
            tooltip = "Delete preset",
        })
        panel:RefreshRowBackgrounds()
    end
    local focusedPanel = focusPresetID and self.presetPanelsByID[focusPresetID] or nil
    if focusedPanel ~= nil then
        self.presetPage:ScrollToChild(focusedPanel)
    else
        self.presetPage:SetScrollPosition(scrollY)
    end
end

function UI:setPage(page)
    self.currentPage = page
    if self.tabs ~= nil then self.tabs:SetActive(PAGE_BY_NAME[page] or 1, false) end
end

function UI:updateStyleControls()
    if self.thicknessText ~= nil then
        self.thicknessText.content = string.format(
            "Outline thickness: %.1f", self.outlineThickness)
    end
end
function UI:isHoverPreviewEnabled()
    return self.hoverPreviewEnabled ~= false
end



function UI:setPanelOpen(open)
    self.panelOpen = open == true
    if self.ribbonRegistration ~= nil then
        self.ribbonRegistration:SetActive(self.panelOpen)
    end
    if self.window ~= nil then
        if self.panelOpen then self.window:Show() else self.window:Close() end
    end
end

local function windowPosition(self)
    local x = 56
    local y = 72
    if self.gameArea ~= nil then
        x = clamp(x, 0, math.max(0, self.gameArea.width - WINDOW_WIDTH))
        y = clamp(y, 0, math.max(0, self.gameArea.height - WINDOW_HEIGHT))
    end
    return x, y
end

function UI:buildWindow()
    local windowX, windowY = windowPosition(self)
    self.window = self.prettyui.Window.new(self.gameArea, {
        title = "Tile Markers",
        x = windowX,
        y = windowY,
        width = WINDOW_WIDTH,
        height = WINDOW_HEIGHT,
        minWidth = WINDOW_WIDTH,
        minHeight = WINDOW_HEIGHT,
        maxWidth = WINDOW_WIDTH,
        maxHeight = WINDOW_HEIGHT,
        onClose = function()
            self.panelOpen = false
            if self.ribbonRegistration ~= nil then
                self.ribbonRegistration:SetActive(false)
            end
        end,
        layout = {
            startY = 10,
            paddingLeft = 12,
            paddingRight = 12,
            rowGap = CONTROL_GAP,
        },
    })

    self.tabs = self.window:AddTabs({
        { text = "Markers", value = "markers" },
        { text = "Presets", value = "presets" },
    }, {
        height = 408,
        onChange = function(_, _, page)
            self:setPage(page)
        end,
        contentLayout = {
            startY = 14,
            paddingLeft = 14,
            paddingRight = 14,
            rowGap = CONTROL_GAP,
        },
    })

    local markerPage = self.tabs:GetPage(1)
    markerPage:AddCheckboxButton({
        {
            text = "Draw over scenery",
            value = "ignore_depth",
            selected = self.ignoreDepth,
            tooltip = "Draw every tile marker over scene geometry, including ground decorations.",
        },
        {
            text = "Show hover preview",
            value = "hover_preview",
            selected = self.hoverPreviewEnabled,
            tooltip = "Preview the tile under the cursor while Ctrl+Shift is held.",
        },
        {
            text = "Render fill",
            value = "fill",
            selected = self.globalStyle.fill,
            tooltip = "Fill tile markers unless overridden in tile customization.",
        },
        {
            text = "Draw outline corners only",
            value = "outlineCornersOnly",
            selected = self.globalStyle.outlineCornersOnly,
            tooltip = "Draw only the outline corners unless overridden in tile customization.",
        },
    }, {
        onChange = function(_, _, changedValue, selected)
            if changedValue == "ignore_depth" then
                self.ignoreDepth = selected == true
                PersistentDB:SetBool(IGNORE_DEPTH_STORAGE_KEY, self.ignoreDepth)
            elseif changedValue == "hover_preview" then
                self.hoverPreviewEnabled = selected == true
                PersistentDB:SetBool(
                    HOVER_PREVIEW_STORAGE_KEY,
                    self.hoverPreviewEnabled)
            elseif changedValue == "fill" or changedValue == "outlineCornersOnly" then
                self.globalStyle[changedValue] = selected == true
                local key = changedValue == "fill"
                    and FILL_STORAGE_KEY or OUTLINE_CORNERS_STORAGE_KEY
                PersistentDB:SetBool(key, selected == true)
            end
        end,
    })
    markerPage:AddText({
        text = "Default marker colour and opacity",
        width = 296,
        height = 32,
        maxLines = 1,
    })
    self.colourPicker = markerPage:AddColourPicker({
        inline = true,
        width = 40,
        height = 32,
        value = self.currentStyle.outlineColour,
        alphaSlider = true,
        windowTitle = "Default marker colour",
        tooltip = "Choose the outline colour. Tile fills use a darker, more transparent version.",
        onChange = function(_, colour)
            self.currentStyle = Styles.fromColour(colour)
            PersistentDB:SetInt(OUTLINE_COLOUR_STORAGE_KEY, colour)
        end,
    })

    self.presetPage = self.tabs:GetPage(2)
    self.presetPage:AddText({
        text = "Presets",
        width = 280,
        height = 32,
        maxLines = 1,
    })
    self.presetPage:AddSpriteButton("PLUS", function()
        self:promptForPresetCreation(false)
    end, {
        inline = true,
        size = 24,
        tooltip = "Add preset",
    })
    self.presetPage:AddSpriteButton("IMPORT", function()
        self:promptForPresetImport()
    end, {
        inline = true,
        size = 24,
        tooltip = "Import preset",
    })
    self:rebuildPresetPanels()

    self.thicknessText = markerPage:AddText({
        text = "",
        width = 344,
        height = 32,
        alignHorizontal = ui.AlignMode.CENTRE,
        maxLines = 1,
    })
    self.thicknessSlider = markerPage:AddSlider({
        min = 0,
        max = 10,
        step = 0.5,
        value = self.outlineThickness,
        tooltip = "Set the outline thickness for every tile marker.",
        onChange = function(_, value)
            self.outlineThickness = clamp(value, 0.0, 10.0)
            PersistentDB:SetInt(
                OUTLINE_THICKNESS_STORAGE_KEY,
                math.floor(self.outlineThickness * 10 + 0.5))
            self:updateStyleControls()
        end,
    })
    markerPage:AddText("Label size")
    self.labelSizeCombo = markerPage:AddComboBox({
        width = 344,
        entries = {},
        tooltip = "Set the label size for every tile marker.",
        onChange = function(_, entryID, _, eventType)
            if eventType ~= ui.SelectionChangeEvent.SELECTED then return end
            self.labelSize = normalizeLabelSize(LABEL_SIZE_BY_ENTRY_ID[entryID])
            PersistentDB:SetInt(FONT_SIZE_STORAGE_KEY, self.labelSize)
        end,
    })
    local labelSizeRoot = self.labelSizeCombo and self.labelSizeCombo.root
    local requestedLabelSizeEntry = LABEL_SIZE_ENTRY_ID[self.labelSize]
    if labelSizeRoot ~= nil and requestedLabelSizeEntry ~= nil then
        local entries = {
            Small = 1,
            Medium = 2,
            Large = 3,
        }
        labelSizeRoot:SetEntries(entries, requestedLabelSizeEntry)
        if not labelSizeRoot.hasSelection
                or labelSizeRoot.selectedID ~= requestedLabelSizeEntry then
            -- Compatibility for clients that interpret selectedID as the
            -- alphabetically sorted label position rather than its mapped ID.
            labelSizeRoot:SetEntries(
                entries,
                LABEL_SIZE_SORTED_POSITION[requestedLabelSizeEntry])
        end
    end
    markerPage:AddText("Hold Ctrl+Shift over a tile, then right-click to mark it or edit its marker.")

    self:updateStyleControls()
    self:setPage(self.currentPage)
    if not self.panelOpen then self.window:Close() end
end

function UI:ensureMounted()
    local currentGameArea = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if currentGameArea == nil then
        self:destroy()
        return false
    end

    if currentGameArea ~= self.gameArea then
        self:destroy()
        self.gameArea = currentGameArea
    end

    if self.canvas ~= nil and self.window ~= nil then
        return true
    end

    self.canvas = ui.Canvas.new(self.gameArea)
    self.canvas:SetPos(0, 0)
    self.canvas:SetSize(0, 0, 1.0, 1.0)
    self.canvas.clickthrough = true

    self:buildWindow()
    return true
end



function UI:isPromptOpen()
    return self.clearPromptWindow ~= nil
        or self.colourPromptWindow ~= nil
        or self.presetCreateWindow ~= nil
        or self.presetImportWindow ~= nil
        or self.presetRenameWindow ~= nil
        or self.presetExportWindow ~= nil
        or self.presetDeleteWindow ~= nil
end

local function trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function centredPopupPosition(self, width, height)
    return clamp(
        math.floor((self.gameArea.width - width) / 2),
        0,
        math.max(0, self.gameArea.width - width)),
        clamp(
            math.floor((self.gameArea.height - height) / 2),
            0,
            math.max(0, self.gameArea.height - height))
end

function UI:finishPresetCreation(accepted)
    local prompt = self.presetCreateWindow
    local createdPreset
    if accepted then
        local handler = self.presetCreateVisible
            and self.presetHandlers.createVisible
            or self.presetHandlers.create
        local success
        success, createdPreset = handler(trim(
            self.presetCreateInput and self.presetCreateInput:GetText() or ""))
        if not success then return end
    end

    self.presetCreateWindow = nil
    self.presetCreateInput = nil
    self.presetCreateVisible = nil
    if prompt ~= nil and prompt.root ~= nil then prompt:Close() end
    if accepted then
        self:rebuildPresetPanels(
            type(createdPreset) == "table" and createdPreset.id or nil)
    end
end

function UI:promptForPresetCreation(visibleOnly)
    if self:isPromptOpen() or self.gameArea == nil then return false end
    local width, height = 352, 176
    local x, y = centredPopupPosition(self, width, height)
    self.presetCreateVisible = visibleOnly == true
    local prompt
    prompt = self.prettyui.Window.new(self.gameArea, {
        title = self.presetCreateVisible
            and "New preset from visible markers"
            or "Add preset",
        x = x,
        y = y,
        width = width,
        height = height,
        minWidth = width,
        minHeight = height,
        maxWidth = width,
        maxHeight = height,
        destroyOnClose = true,
        onClose = function()
            if self.presetCreateWindow == prompt then
                self.presetCreateWindow = nil
                self.presetCreateInput = nil
                self.presetCreateVisible = nil
            end
        end,
        layout = {
            startY = 10,
            paddingLeft = 12,
            paddingRight = 12,
            rowGap = 8,
        },
    })
    self.presetCreateWindow = prompt
    self.presetCreateInput = prompt:AddTextField({
        placeholder = "Preset name",
        maxLength = 32,
        onSubmit = function() self:finishPresetCreation(true) end,
    })
    prompt:AddFancyButton("Save", function()
        self:finishPresetCreation(true)
    end, {
        width = 152,
        variant = "positive",
    })
    prompt:AddFancyButton("Cancel", function()
        self:finishPresetCreation(false)
    end, {
        inline = true,
        width = 152,
        variant = "negative",
    })
    return true
end

function UI:finishPresetImport(accepted)
    local prompt = self.presetImportWindow
    local importedPreset
    if accepted then
        local success
        success, importedPreset = self.presetHandlers.import(
            self.presetImportInput and self.presetImportInput:GetText() or "")
        if not success then return end
    end
    self.presetImportWindow = nil
    self.presetImportInput = nil
    if prompt ~= nil and prompt.root ~= nil then prompt:Close() end
    if accepted then
        self:rebuildPresetPanels(
            type(importedPreset) == "table" and importedPreset.id or nil)
    end
end

function UI:promptForPresetImport()
    if self:isPromptOpen() or self.gameArea == nil then return false end
    local width, height = 416, 176
    local x, y = centredPopupPosition(self, width, height)
    local prompt
    prompt = self.prettyui.Window.new(self.gameArea, {
        title = "Import preset",
        x = x,
        y = y,
        width = width,
        height = height,
        minWidth = width,
        minHeight = height,
        maxWidth = width,
        maxHeight = height,
        destroyOnClose = true,
        onClose = function()
            if self.presetImportWindow == prompt then
                self.presetImportWindow = nil
                self.presetImportInput = nil
            end
        end,
        layout = {
            startY = 10,
            paddingLeft = 12,
            paddingRight = 12,
            rowGap = 8,
        },
    })
    self.presetImportWindow = prompt
    self.presetImportInput = prompt:AddTextField({
        placeholder = "Paste TM preset token here",
        maxLength = 65535,
        onSubmit = function() self:finishPresetImport(true) end,
    })
    prompt:AddFancyButton("Import", function()
        self:finishPresetImport(true)
    end, {
        width = 184,
        variant = "positive",
    })
    prompt:AddFancyButton("Cancel", function()
        self:finishPresetImport(false)
    end, {
        inline = true,
        width = 184,
        variant = "negative",
    })
    return true
end

function UI:finishPresetRename(accepted)
    local prompt = self.presetRenameWindow
    if accepted then
        local success = self.presetHandlers.rename(
            self.presetRenameID,
            trim(self.presetRenameInput and self.presetRenameInput:GetText() or ""))
        if not success then return end
    end
    self.presetRenameWindow = nil
    self.presetRenameInput = nil
    self.presetRenameID = nil
    if prompt ~= nil and prompt.root ~= nil then prompt:Close() end
    if accepted then self:rebuildPresetPanels() end
end

function UI:promptForPresetRename(presetID, presetName)
    if self:isPromptOpen() or self.gameArea == nil then return false end
    local width, height = 352, 176
    local x, y = centredPopupPosition(self, width, height)
    self.presetRenameID = presetID
    local prompt
    prompt = self.prettyui.Window.new(self.gameArea, {
        title = "Rename preset",
        x = x,
        y = y,
        width = width,
        height = height,
        minWidth = width,
        minHeight = height,
        maxWidth = width,
        maxHeight = height,
        destroyOnClose = true,
        onClose = function()
            if self.presetRenameWindow == prompt then
                self.presetRenameWindow = nil
                self.presetRenameInput = nil
                self.presetRenameID = nil
            end
        end,
        layout = {
            startY = 10,
            paddingLeft = 12,
            paddingRight = 12,
            rowGap = 8,
        },
    })
    self.presetRenameWindow = prompt
    self.presetRenameInput = prompt:AddTextField({
        text = presetName,
        placeholder = "Preset name",
        maxLength = 32,
        onSubmit = function() self:finishPresetRename(true) end,
    })
    prompt:AddFancyButton("Rename", function()
        self:finishPresetRename(true)
    end, {
        width = 152,
        variant = "positive",
    })
    prompt:AddFancyButton("Cancel", function()
        self:finishPresetRename(false)
    end, {
        inline = true,
        width = 152,
        variant = "negative",
    })
    return true
end

function UI:finishPresetDelete(confirmed)
    local prompt = self.presetDeleteWindow
    if confirmed then
        local success = self.presetHandlers.delete(self.presetDeleteID)
        if not success then return end
    end
    self.presetDeleteWindow = nil
    self.presetDeleteID = nil
    if prompt ~= nil and prompt.root ~= nil then prompt:Close() end
    if confirmed then self:rebuildPresetPanels() end
end

function UI:promptForPresetDelete(presetID, presetName)
    if self:isPromptOpen() or self.gameArea == nil then return false end
    local width, height = 416, 176
    local x, y = centredPopupPosition(self, width, height)
    self.presetDeleteID = presetID
    local prompt
    prompt = self.prettyui.Window.new(self.gameArea, {
        title = "Delete preset",
        x = x,
        y = y,
        width = width,
        height = height,
        minWidth = width,
        minHeight = height,
        maxWidth = width,
        maxHeight = height,
        destroyOnClose = true,
        onClose = function()
            if self.presetDeleteWindow == prompt then
                self.presetDeleteWindow = nil
                self.presetDeleteID = nil
            end
        end,
        layout = {
            startY = 10,
            paddingLeft = 12,
            paddingRight = 12,
            rowGap = 8,
        },
    })
    self.presetDeleteWindow = prompt
    prompt:AddText({
        text = string.format(
            "Are you sure you want to delete \"%s\"? This cannot be undone.",
            tostring(presetName or "preset")),
        height = 48,
        maxLines = 2,
    })
    prompt:AddFancyButton("Delete", function()
        self:finishPresetDelete(true)
    end, {
        width = 184,
        variant = "negative",
    })
    prompt:AddFancyButton("Cancel", function()
        self:finishPresetDelete(false)
    end, {
        inline = true,
        width = 184,
    })
    return true
end

function UI:promptForPresetExport(presetID, presetName)
    if self:isPromptOpen() or self.gameArea == nil then return false end
    local success, token = self.presetHandlers.export(presetID)
    if not success then return false end
    local width, height = 416, 192
    local x, y = centredPopupPosition(self, width, height)
    local prompt
    prompt = self.prettyui.Window.new(self.gameArea, {
        title = "Export " .. tostring(presetName or "preset"),
        x = x,
        y = y,
        width = width,
        height = height,
        minWidth = width,
        minHeight = height,
        maxWidth = width,
        maxHeight = height,
        destroyOnClose = true,
        onClose = function()
            if self.presetExportWindow == prompt then
                self.presetExportWindow = nil
                self.presetExportInput = nil
            end
        end,
        layout = {
            startY = 10,
            paddingLeft = 12,
            paddingRight = 12,
            rowGap = 8,
        },
    })
    self.presetExportWindow = prompt
    prompt:AddText({
        text = "Click the field below, press <col=F2C66D>Ctrl+A</col> to select the full export string, then press <col=F2C66D>Ctrl+C</col> to copy it.",
        height = 48,
        maxLines = 2,
    })
    self.presetExportInput = prompt:AddTextField({
        text = token,
        maxLength = 65535,
    })
    prompt:AddFancyButton("Close", function()
        local exportPrompt = self.presetExportWindow
        self.presetExportWindow = nil
        self.presetExportInput = nil
        if exportPrompt ~= nil and exportPrompt.root ~= nil then
            exportPrompt:Close()
        end
    end, {
        width = 368,
    })
    return true
end

function UI:finishClearPrompt(accepted)
    local prompt = self.clearPromptWindow
    local callback = accepted and self.clearPromptCallback or nil

    self.clearPromptWindow = nil
    self.clearPromptCallback = nil

    if prompt ~= nil and prompt.root ~= nil then
        prompt:Close()
    end
    if callback ~= nil then callback() end
end

function UI:promptForClear(tileCount, callback)
    if self:isPromptOpen() or self.gameArea == nil then return false end

    tileCount = math.max(0, math.floor(tonumber(tileCount) or 0))
    local width = 416
    local height = 136
    local x = clamp(math.floor((self.gameArea.width - width) / 2), 0, math.max(0, self.gameArea.width - width))
    local y = clamp(math.floor((self.gameArea.height - height) / 2), 0, math.max(0, self.gameArea.height - height))

    self.clearPromptCallback = callback
    local prompt
    prompt = self.prettyui.Window.new(self.gameArea, {
        title = "Clear visible markers",
        x = x,
        y = y,
        width = width,
        height = height,
        minWidth = width,
        minHeight = height,
        maxWidth = width,
        maxHeight = height,
        destroyOnClose = true,
        onClose = function()
            if self.clearPromptWindow == prompt then
                self.clearPromptWindow = nil
                self.clearPromptCallback = nil
            end
        end,
        layout = {
            startY = 10,
            paddingLeft = 12,
            paddingRight = 12,
            rowGap = 8,
        },
    })
    self.clearPromptWindow = prompt
    prompt:AddText({
        text = string.format(
            "Are you sure you wish to clear <col=F2C66D>%d</col> tilemarkers?",
            tileCount),
        height = 32,
        maxLines = 1,
    })
    prompt:AddFancyButton("Yes", function()
        self:finishClearPrompt(true)
    end, {
        width = 184,
        variant = "positive",
    })
    prompt:AddFancyButton("No", function()
        self:finishClearPrompt(false)
    end, {
        inline = true,
        width = 184,
        variant = "negative",
    })
    return true
end

function UI:rememberColour(colour)
    colour = Styles.fromColour(colour).outlineColour
    local recent = { colour }
    for _, existing in ipairs(self.recentColours) do
        if existing ~= colour and #recent < MAX_RECENT_COLOURS then
            recent[#recent + 1] = existing
        end
    end
    self.recentColours = recent
    PersistentDB:SetString(
        RECENT_COLOURS_STORAGE_KEY,
        encodeRecentColours(self.recentColours))
end

local function colourPromptValues(self)
    return trim(
            self.colourPromptLabelInput
                and self.colourPromptLabelInput:GetText()
                or ""),
        self.colourPromptColour,
        self.colourPromptFill,
        self.colourPromptOutlineCornersOnly
end

local function clearColourPromptState(self)
    self.colourPromptWindow = nil
    self.colourPromptLabelInput = nil
    self.colourPromptPicker = nil
    self.colourPromptColour = nil
    self.colourPromptFill = nil
    self.colourPromptOutlineCornersOnly = nil
    self.colourPromptActions = nil
end

local function previewColourPrompt(self)
    local preview = self.colourPromptActions and self.colourPromptActions.preview
    if preview ~= nil then preview(colourPromptValues(self)) end
end

function UI:finishColourPrompt(accepted)
    local prompt = self.colourPromptWindow
    local label, colour, renderFill, outlineCornersOnly
    if accepted then
        label, colour, renderFill, outlineCornersOnly = colourPromptValues(self)
    end
    local actions = self.colourPromptActions
    local callback = actions
        and (accepted and actions.confirm or actions.cancel)
        or nil

    clearColourPromptState(self)
    if prompt ~= nil and prompt.root ~= nil then prompt:Close() end

    if accepted then
        self:rememberColour(colour)
        if callback ~= nil then
            callback(label, colour, renderFill, outlineCornersOnly)
        end
    elseif callback ~= nil then
        callback()
    end
end

function UI:promptForCustomization(
    initialLabel,
    initialColour,
    initialFill,
    initialOutlineCornersOnly,
    actions)
    if self:isPromptOpen() or self.gameArea == nil then return false end

    local width = 384
    local height = 328
    local x = clamp(
        math.floor((self.gameArea.width - width) / 2),
        0,
        math.max(0, self.gameArea.width - width))
    local y = clamp(
        math.floor((self.gameArea.height - height) / 2),
        0,
        math.max(0, self.gameArea.height - height))

    self.colourPromptColour = Styles.fromColour(initialColour).outlineColour
    -- Keep inherited values nil until their checkbox is changed.
    self.colourPromptFill = initialFill
    self.colourPromptOutlineCornersOnly = initialOutlineCornersOnly
    self.colourPromptActions = actions
    local prompt
    prompt = self.prettyui.Window.new(self.gameArea, {
        title = "Tile customization",
        x = x,
        y = y,
        width = width,
        height = height,
        minWidth = width,
        minHeight = height,
        maxWidth = width,
        maxHeight = height,
        destroyOnClose = true,
        onClose = function()
            if self.colourPromptWindow == prompt then
                local cancel = self.colourPromptActions
                    and self.colourPromptActions.cancel
                    or nil
                clearColourPromptState(self)
                if cancel ~= nil then cancel() end
            end
        end,
        layout = {
            startY = 10,
            paddingLeft = 12,
            paddingRight = 12,
            rowGap = 8,
        },
    })
    self.colourPromptWindow = prompt
    self.colourPromptLabelInput = prompt:AddTextField({
        placeholder = "Tile label (optional)",
        text = initialLabel,
        maxLength = 32,
        onSubmit = function()
            self:finishColourPrompt(true)
        end,
        onChange = function()
            previewColourPrompt(self)
        end,
    })
    prompt:AddCheckboxButton({
        {
            text = "Render fill",
            value = "render_fill",
            selected = initialFill == true
                or (initialFill == nil and self.globalStyle.fill),
        },
        {
            text = "Draw outline corners only",
            value = "outline_corners_only",
            selected = initialOutlineCornersOnly == true
                or (initialOutlineCornersOnly == nil and self.globalStyle.outlineCornersOnly),
        },
    }, {
        onChange = function(_, _, value, selected)
            if value == "render_fill" then
                self.colourPromptFill = selected == true
            elseif value == "outline_corners_only" then
                self.colourPromptOutlineCornersOnly = selected == true
            end
            previewColourPrompt(self)
        end,
    })
    prompt:AddText({
        text = "Choose the tile outline colour.",
        width = 296,
        height = 32,
        maxLines = 1,
    })
    self.colourPromptPicker = prompt:AddColourPicker({
        inline = true,
        width = 40,
        height = 32,
        value = self.colourPromptColour,
        alphaSlider = true,
        windowTitle = "Tile colour",
        onChange = function(_, colour)
            self.colourPromptColour = colour
            previewColourPrompt(self)
        end,
    })
    prompt:AddText("Recently used colours")
    for index, colour in ipairs(self.recentColours) do
        local button = prompt:AddSimpleButton("", function()
            self.colourPromptPicker:SetValue(colour)
        end, {
            inline = index > 1,
            width = 32,
            height = 32,
            tooltip = "Use recent colour",
        })
        local swatch = ui.Rectangle.new(button.root)
        swatch:SetPos(4, 4)
        swatch:SetSize(24, 24)
        swatch.fill = true
        swatch.rgba = colour
        swatch.clickthrough = true
    end
    prompt:AddFancyButton("Confirm", function()
        self:finishColourPrompt(true)
    end, {
        width = 168,
        variant = "positive",
    })
    prompt:AddFancyButton("Cancel", function()
        self:finishColourPrompt(false)
    end, {
        inline = true,
        width = 168,
        variant = "negative",
    })
    return true
end

function UI:getStyle()
    return Styles.copy(self.currentStyle)
end

function UI:drawTile(coord, metadata, style)
    style = style or Styles.normalize(metadata, self.globalStyle)
    local drawn = self.renderer.Tile{
        coordGrid = coord,
        outlineColour = style.outlineColour,
        fillColour = style.fillColour,
        fill = style.fill,
        outlineCornersOnly = style.outlineCornersOnly,
        outlineThickness = self.outlineThickness,
        ignoreDepth = self.ignoreDepth,
    }
    if not drawn then return false end

    local centre = ScreenConvert.CoordFineToScreen(coord:ToCoordFine(true), 100)
    if metadata ~= nil and metadata.text ~= nil and metadata.text ~= "" and centre ~= nil then
        local labelStyle = {
            outlineColour = labelColour(style.outlineColour),
            fontSize = self.labelSize,
        }
        local labelHeight = math.max(36, self.labelSize + 16)
        self.canvas:AddText(
            round(centre.x - 100),
            round(centre.y - labelHeight / 2),
            200,
            labelHeight,
            metadata.text,
            labelTextConfig(labelStyle))
    end

    return true
end

function UI:draw(tiles, hover)
    self.canvas:Clear()

    local entries = {}
    local entriesByPosition = {}
    for coord, metadata in pairs(tiles) do
        local position = gridPosition(coord)
        local entry = {
            coord = coord,
            metadata = metadata,
            position = position,
        }
        if position ~= nil then
            entriesByPosition[position.key] = entry
        else
            entries[#entries + 1] = entry
        end
    end

    if hover ~= nil then
        local hoverPosition = gridPosition(hover)
        local existing = hoverPosition
            and entriesByPosition[hoverPosition.key]
            or nil
        if existing ~= nil then
            existing.coord = hover
            existing.style = markedHoverStyle(existing.metadata, self.globalStyle)
        else
            local entry = {
                coord = hover,
                metadata = nil,
                style = EMPTY_HOVER_STYLE,
                position = hoverPosition,
            }
            if hoverPosition ~= nil then
                entriesByPosition[hoverPosition.key] = entry
            else
                entries[#entries + 1] = entry
            end
        end
    end

    for _, entry in pairs(entriesByPosition) do
        self:drawTile(entry.coord, entry.metadata, entry.style)
    end
    for _, entry in ipairs(entries) do
        self:drawTile(entry.coord, entry.metadata, entry.style)
    end
end

return UI
