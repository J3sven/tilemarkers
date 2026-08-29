local Tiles = require("src/tiles")
local Draw = require("src/draw")
local Minimenu = require("src/minimenu")
local Presets = require("src/presets")
local PresetEditor = require("src/preset_editor")
local RegionBindings = require("src/region_bindings")
local UI = require("src/ui")

local EVENT_ID = "tileMarker"
local DRAW_DISTANCE = 30

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
                sourceCoords[#sourceCoords + 1] = binding.source
            end
        end
    else
        for coord in pairs(visibleTiles) do
            sourceCoords[#sourceCoords + 1] = coord
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

local function createPreset(name, sourceCoords)
    local tiles = sourceCoords == nil
        and Tiles:export()
        or Tiles:exportCoords(sourceCoords)
    local success, result = Presets:create(name, tiles, true)
    if not success then return success, result end

    local cleared
    if sourceCoords == nil then
        cleared = Tiles:clear()
    else
        cleared = Tiles:removeAll(sourceCoords)
    end
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
            return createPreset(name, nil)
        end,
        createVisible = function(name)
            return createPreset(name, visibleMarkerSources())
        end,
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

Event.Draw.Subscribe(EVENT_ID, function()
    Draw.BeginFrame()
    if not UI:ensureMounted() then
        return
    end

    local player = Player.IsAvailable() and Player.GetEntity() or nil
    if player == nil or not player.isValid then
        UI:draw({}, nil)
        return
    end

    local regionBindings = RegionBindings.resolveArea(player.coordGrid, DRAW_DISTANCE)
    local tiles = Tiles:query(player.coordGrid, DRAW_DISTANCE, regionBindings)
    local excludedPresetID = PresetEditor:isActive()
        and PresetEditor.presetID
        or nil
    local presetTiles = Presets:query(
        player.coordGrid,
        DRAW_DISTANCE,
        regionBindings,
        excludedPresetID)
    for coord, metadata in pairs(presetTiles) do
        tiles[coord] = metadata
    end
    if PresetEditor:isActive() then
        local editedTiles = PresetEditor:query(
            player.coordGrid,
            DRAW_DISTANCE,
            regionBindings)
        for coord, metadata in pairs(editedTiles) do
            tiles[coord] = metadata
        end
    end
    local hover = Minimenu.getHover()
    UI:draw(tiles, hover)
end)

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
        UI:setPanelOpen(false)
        UI:destroy()
        RegionBindings.clear()
        Draw.Reset()
    end
end)

function PluginShutdown()
    Event.Draw.Unsubscribe(EVENT_ID)
    Minimenu.shutdown()
    PresetEditor:cancel()
    Event.GameStateChanged.Unsubscribe(EVENT_ID)
    UI:shutdown()
    Draw.Reset()
end
