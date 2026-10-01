local Tiles = require("src/tiles")
local Draw = require("src/draw")
local Minimenu = require("src/minimenu")
local Presets = require("src/presets")
local PresetEditor = require("src/preset_editor")
local RegionBindings = require("src/region_bindings")
local UI = require("src/ui")

local EVENT_ID = "tileMarker"
local DRAW_DISTANCE = 30
local RESIDENT_MARGIN = 16
local RESIDENT_RANGE = DRAW_DISTANCE + RESIDENT_MARGIN + 1
local DRAW_DISTANCE_FINE = DRAW_DISTANCE * 512
local residentTiles = {}
local residentAnchor
local tilesRevision, presetsRevision, editorRevision
local boundsX, boundsZ, boundsWidth, boundsHeight

local function resetMarkers()
    Draw.Reset()
    RegionBindings.clear()
    residentTiles = {}
    residentAnchor = nil
    UI.renderTiles = nil
    UI.markerLabels = {}
end

log("loaded")
Draw.Reset()

local function visibleMarkerSources()
    local player = Player.IsAvailable() and Player.GetEntity() or nil
    if player == nil or not player.isValid then
        return {}
    end

    local regionBindings = RegionBindings.resolveArea(player.coordGrid, DRAW_DISTANCE)
    local visibleTiles = Tiles:query(player.coordGrid, DRAW_DISTANCE, regionBindings)
    local sourceCoords = {}
    if regionBindings ~= nil then
        for _, binding in ipairs(regionBindings) do
            if visibleTiles[binding.target] ~= nil then
                table.insert(sourceCoords, binding.source)
            end
        end
    else
        for coord in pairs(visibleTiles) do
            table.insert(sourceCoords, coord)
        end
    end
    return sourceCoords
end

local function promptClearVisibleMarkers()
    local sourceCoords = visibleMarkerSources()
    UI:promptForClear(#sourceCoords, function()
        Tiles:removeAll(sourceCoords)
    end)
end

local function createVisiblePreset(name)
    local sourceCoords = visibleMarkerSources()
    local tiles = Tiles:exportCoords(sourceCoords)
    if #tiles == 0 then return false, "Mark at least one tile first." end
    local success, result = Presets:create(name, tiles, true)
    if not success then return success, result end

    local cleared = Tiles:removeAll(sourceCoords)
    if not cleared then
        Presets:delete(result.id)
        return false, "Could not remove the source tiles; preset was not kept."
    end
    return true, result
end

UI:init(
    {
        list = function()
            return Presets:list()
        end,
        isActive = function(id)
            return Presets:isActive(id)
        end,
        setActive = function(id, active)
            local success, message = Presets:setActive(id, active)
            if success and message == nil then
                message = active and "Preset activated." or "Preset deactivated."
            end
            return success, message
        end,
        create = function(name)
            return Presets:create(name, {}, true)
        end,
        createVisible = createVisiblePreset,
        rename = function(id, name)
            return Presets:rename(id, name)
        end,
        delete = function(id)
            return Presets:delete(id)
        end,
        export = function(id)
            return Presets:export(id)
        end,
        import = function(source)
            return Presets:import(source)
        end,
        startEdit = function(id)
            local preset = Presets:get(id)
            if preset == nil then return false, "Preset no longer exists." end
            if not PresetEditor:begin(preset) then
                return false, "Another preset is already being edited."
            end
            return true
        end,
        saveEdit = function()
            if not PresetEditor:isActive() then
                return false, "No preset is being edited."
            end
            local success, message = Presets:updateTiles(
                PresetEditor.presetID,
                PresetEditor:export())
            if success then PresetEditor:cancel() end
            return success, message
        end,
        cancelEdit = function()
            PresetEditor:cancel()
            return true
        end,
    },
    prettyui)

Event.Logic.Subscribe(EVENT_ID, function()
    local player = Player.IsAvailable() and Player.GetEntity() or nil
    if player == nil or not player.isValid or not UI:ensureMounted() then
        if residentAnchor ~= nil then resetMarkers() end
        return
    end

    local bounds = World.GetMapSquareBounds()
    if bounds == nil then
        if residentAnchor ~= nil then resetMarkers() end
        return
    end
    if bounds.x ~= boundsX or bounds.y ~= boundsZ
        or bounds.width ~= boundsWidth or bounds.height ~= boundsHeight then
        resetMarkers()
        boundsX, boundsZ = bounds.x, bounds.y
        boundsWidth, boundsHeight = bounds.width, bounds.height
    end

    local coord = player.coordGrid
    local moved = residentAnchor == nil or coord.level ~= residentAnchor.level
        or math.abs(coord.x - residentAnchor.x) >= RESIDENT_MARGIN
        or math.abs(coord.z - residentAnchor.z) >= RESIDENT_MARGIN
    if moved or tilesRevision ~= Tiles.revision
        or presetsRevision ~= Presets.revision or editorRevision ~= PresetEditor.revision then
        if residentAnchor ~= nil and coord.level ~= residentAnchor.level then
            resetMarkers()
        end
        residentAnchor = coord
        local bindings = RegionBindings.resolveArea(coord, RESIDENT_RANGE)
        local byPosition = {}
        local function merge(tiles)
            for tileCoord, metadata in pairs(tiles) do
                byPosition[tileCoord:ToPacked()] = { coord = tileCoord, metadata = metadata }
            end
        end
        merge(Tiles:query(coord, RESIDENT_RANGE, bindings))
        merge(Presets:query(
            coord, RESIDENT_RANGE, bindings,
            PresetEditor:isActive() and PresetEditor.presetID or nil))
        if PresetEditor:isActive() then
            merge(PresetEditor:query(coord, RESIDENT_RANGE, bindings))
        end
        residentTiles = {}
        for _, entry in pairs(byPosition) do
            residentTiles[entry.coord] = entry.metadata
        end
        tilesRevision, presetsRevision, editorRevision =
            Tiles.revision, Presets.revision, PresetEditor.revision
    end
    UI:syncMarkers(residentTiles, Minimenu.getHover(), DRAW_DISTANCE_FINE)
end)

Event.Draw.Subscribe(EVENT_ID, function()
    if not UI:ensureMounted() then return end
    local player = Player.IsAvailable() and Player.GetEntity() or nil
    if player == nil or not player.isValid then
        UI:drawLabels(nil)
        return
    end
    Draw.UpdateCamera()
    UI:drawLabels(player.position, player.coordGrid.level)
end)

Event.RegionCreated.Subscribe(EVENT_ID, resetMarkers)
Event.RegionUpdated.Subscribe(EVENT_ID, resetMarkers)

Minimenu.start({
    clearVisible = promptClearVisibleMarkers,
    createVisiblePreset = function()
        UI:promptForPresetCreation(true)
    end,
    importPreset = function()
        UI:promptForPresetImport()
    end,
    findPresetAt = function(source)
        return Presets:findActiveAt(source)
    end,
    startPresetEdit = function(id, name)
        if not UI:ensureMounted() then return false end
        return UI:startPresetEdit(id, name)
    end,
    editStore = function()
        return PresetEditor:isActive() and PresetEditor or nil
    end,
})

Event.GameStateChanged.Subscribe(EVENT_ID, function(gameStateChangedEvent)
    if gameStateChangedEvent.newState ~= GameState.GAME then
        Minimenu.reset()
        PresetEditor:cancel()
        UI:destroySettings()
        UI:destroyContent()
        UI:destroy()
        resetMarkers()
    end
end)

function PluginShutdown()
    Event.Draw.Unsubscribe(EVENT_ID)
    Event.Logic.Unsubscribe(EVENT_ID)
    Event.RegionCreated.Unsubscribe(EVENT_ID)
    Event.RegionUpdated.Unsubscribe(EVENT_ID)
    Minimenu.shutdown()
    PresetEditor:cancel()
    Event.GameStateChanged.Unsubscribe(EVENT_ID)
    UI:shutdown()
    Draw.Reset()
end
