local Codec = require("src/preset_codec")
local Styles = require("src/styles")

local STORAGE_KEY = "tilePresets"
local EXPORT_VERSION = 2
local COLOUR_ENCODING = "hex"
local storedData = PersistentDB:GetStructuredData(STORAGE_KEY)

local Presets = {
    data = storedData or {},
}

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$") or ""
end

local function sanitizeTile(tile)
    if type(tile) ~= "table" then
        return nil
    end

    local x = tonumber(tile.x)
    local z = tonumber(tile.z)
    local level = tonumber(tile.level) or 0
    if x == nil or z == nil or level < 0 or level > 3 then
        return nil
    end

    local result = {
        x = math.floor(x),
        z = math.floor(z),
        level = math.floor(level),
    }
    local style = Styles.normalize(tile)
    result.outlineColour = style.outlineColour
    result.fillColour = style.fillColour
    result.fill = style.fill
    result.outlineCornersOnly = style.outlineCornersOnly
    result.outlineThickness = style.outlineThickness
    local label = trim(tile.label or tile.text)
    if label ~= "" then
        result.label = label:sub(1, 32)
    end
    return result
end

local function normalizeTiles(tiles)
    local result = {}
    local seen = {}
    if type(tiles) ~= "table" then
        return result
    end
    for _, tile in ipairs(tiles) do
        local normalized = sanitizeTile(tile)
        if normalized ~= nil then
            local key = string.format("%d:%d:%d", normalized.level, normalized.x, normalized.z)
            if not seen[key] then
                seen[key] = true
                result[#result + 1] = normalized
            end
        end
    end
    table.sort(result, function(left, right)
        if left.level ~= right.level then
            return left.level < right.level
        elseif left.x ~= right.x then
            return left.x < right.x
        end
        return left.z < right.z
    end)
    return result
end

local function normalizeData(data)
    local normalized = {
        version = EXPORT_VERSION,
        nextId = math.max(1, tonumber(data.nextId) or 1),
        activeIds = {},
        presets = {},
    }
    local knownIds = {}
    for _, preset in ipairs(type(data.presets) == "table" and data.presets or {}) do
        if type(preset) == "table" then
            local tiles = normalizeTiles(preset.tiles)
            local name = trim(preset.name)
            local id = trim(preset.id)
            if id == "" then
                id = "preset_" .. tostring(normalized.nextId)
                normalized.nextId = normalized.nextId + 1
            end
            local numericId = tonumber(id:match("^preset_(%d+)$"))
            if numericId ~= nil then
                normalized.nextId = math.max(normalized.nextId, numericId + 1)
            end
            if name ~= "" and #tiles > 0 and not knownIds[id] then
                knownIds[id] = true
                normalized.presets[#normalized.presets + 1] = {
                    id = id,
                    name = name:sub(1, 32),
                    tiles = tiles,
                }
            end
        end
    end
    for _, id in ipairs(type(data.activeIds) == "table" and data.activeIds or {}) do
        if knownIds[id] then
            normalized.activeIds[#normalized.activeIds + 1] = id
        end
    end
    return normalized
end

Presets.data = normalizeData(Presets.data)

local function storageData(data)
    local stored = {
        version = data.version,
        nextId = data.nextId,
        colourEncoding = COLOUR_ENCODING,
        activeIds = {},
        presets = {},
    }
    for index, id in ipairs(data.activeIds) do
        stored.activeIds[index] = id
    end
    for presetIndex, preset in ipairs(data.presets) do
        local storedPreset = {
            id = preset.id,
            name = preset.name,
            tiles = {},
        }
        stored.presets[presetIndex] = storedPreset
        for tileIndex, tile in ipairs(preset.tiles) do
            storedPreset.tiles[tileIndex] = {
                x = tile.x,
                z = tile.z,
                level = tile.level,
                label = tile.label,
                outlineColour = Styles.encodeColour(tile.outlineColour),
                fillColour = Styles.encodeColour(tile.fillColour),
                fill = tile.fill,
                outlineCornersOnly = tile.outlineCornersOnly,
                outlineThickness = tile.outlineThickness,
            }
        end
    end
    return stored
end

function Presets:save()
    return PersistentDB:SetStructuredData(STORAGE_KEY, storageData(self.data))
end

if storedData ~= nil and storedData.colourEncoding ~= COLOUR_ENCODING then
    Presets:save()
end

function Presets:list()
    return self.data.presets
end

function Presets:get(id)
    for _, preset in ipairs(self.data.presets) do
        if preset.id == id then
            return preset
        end
    end
    return nil
end

function Presets:isActive(id)
    for _, activeId in ipairs(self.data.activeIds) do
        if activeId == id then
            return true
        end
    end
    return false
end

function Presets:findActiveAt(coord)
    if coord == nil then return nil end

    for presetIndex = #self.data.presets, 1, -1 do
        local preset = self.data.presets[presetIndex]
        if self:isActive(preset.id) then
            for _, tile in ipairs(preset.tiles) do
                if tile.level == coord.level
                    and tile.x == coord.x
                    and tile.z == coord.z then
                    return preset
                end
            end
        end
    end
    return nil
end

function Presets:setActive(id, active)
    if self:get(id) == nil then
        return false, "No preset selected."
    end
    for index, activeId in ipairs(self.data.activeIds) do
        if activeId == id then
            if not active then
                table.remove(self.data.activeIds, index)
                self:save()
            end
            return true
        end
    end
    if active then
        self.data.activeIds[#self.data.activeIds + 1] = id
        self:save()
    end
    return true
end

function Presets:create(name, tiles, active)
    name = trim(name)
    tiles = normalizeTiles(tiles)
    if name == "" then
        return false, "Enter a preset name."
    elseif #tiles == 0 then
        return false, "Mark at least one tile first."
    end
    local previousNextId = self.data.nextId
    local id = "preset_" .. tostring(previousNextId)
    self.data.nextId = self.data.nextId + 1
    local preset = { id = id, name = name:sub(1, 32), tiles = tiles }
    self.data.presets[#self.data.presets + 1] = preset
    if active then
        self.data.activeIds[#self.data.activeIds + 1] = id
    end
    if not self:save() then
        table.remove(self.data.presets)
        if active then
            table.remove(self.data.activeIds)
        end
        self.data.nextId = previousNextId
        return false, "Could not save preset."
    end
    return true, preset
end

function Presets:rename(id, name)
    local preset = self:get(id)
    if preset == nil then
        return false, "No preset selected."
    end
    name = trim(name)
    if name == "" then
        return false, "Enter a preset name."
    end
    preset.name = name:sub(1, 32)
    self:save()
    return true, "Preset renamed."
end

function Presets:updateTiles(id, tiles)
    local preset = self:get(id)
    if preset == nil then
        return false, "Preset no longer exists."
    end
    local normalized = normalizeTiles(tiles)
    if #normalized == 0 then
        return false, "A preset must contain at least one tile."
    end

    local previousTiles = preset.tiles
    preset.tiles = normalized
    if not self:save() then
        preset.tiles = previousTiles
        return false, "Could not save preset changes."
    end
    return true, "Preset changes saved."
end

function Presets:delete(id)
    for index, preset in ipairs(self.data.presets) do
        if preset.id == id then
            table.remove(self.data.presets, index)
            for activeIndex = #self.data.activeIds, 1, -1 do
                if self.data.activeIds[activeIndex] == id then
                    table.remove(self.data.activeIds, activeIndex)
                end
            end
            self:save()
            return true, "Preset deleted."
        end
    end
    return false, "No preset selected."
end

function Presets:export(id)
    local preset = self:get(id)
    if preset == nil then
        return false, "No preset selected."
    end
    local encoded = Codec.encode(preset.name, preset.tiles)
    if encoded == nil then
        return false, "Could not encode preset."
    end
    return true, encoded
end

function Presets:import(source)
    local decoded, decodeError = Codec.decode(trim(source))
    if decoded == nil then
        return false, decodeError
    end
    return self:create(decoded.name or "Imported preset", decoded.tiles, true)
end

local function coordKey(coord)
    return string.format("%d:%d:%d", coord.level, coord.x, coord.z)
end

function Presets:query(from, range, regionBindings, excludedPresetID)
    local byPacked = {}

    if regionBindings ~= nil then
        local sourceMetadata = {}
        for _, preset in ipairs(self.data.presets) do
            if preset.id ~= excludedPresetID and self:isActive(preset.id) then
                for _, tile in ipairs(preset.tiles) do
                    sourceMetadata[string.format(
                        "%d:%d:%d", tile.level, tile.x, tile.z)] = {
                        text = tile.label,
                        outlineColour = tile.outlineColour,
                        fillColour = tile.fillColour,
                        fill = tile.fill,
                        outlineCornersOnly = tile.outlineCornersOnly,
                        outlineThickness = tile.outlineThickness,
                    }
                end
            end
        end
        for _, binding in ipairs(regionBindings) do
            local metadata = sourceMetadata[coordKey(binding.source)]
            if metadata ~= nil then
                byPacked[binding.target:ToPacked()] = {
                    coord = binding.target,
                    metadata = metadata,
                }
            end
        end
    else
        for _, preset in ipairs(self.data.presets) do
            if preset.id ~= excludedPresetID and self:isActive(preset.id) then
                for _, tile in ipairs(preset.tiles) do
                    if tile.level == from.level
                        and math.abs(tile.x - from.x) <= range
                        and math.abs(tile.z - from.z) <= range then
                        local coord = CoordGrid.new(
                            tile.level,
                            tile.x // 64,
                            tile.z // 64,
                            tile.x % 64,
                            tile.z % 64)
                        byPacked[coord:ToPacked()] = {
                            coord = coord,
                            metadata = {
                                text = tile.label,
                                outlineColour = tile.outlineColour,
                                fillColour = tile.fillColour,
                                fill = tile.fill,
                                outlineCornersOnly = tile.outlineCornersOnly,
                                outlineThickness = tile.outlineThickness,
                            },
                        }
                    end
                end
            end
        end
    end
    local result = {}
    for _, entry in pairs(byPacked) do
        result[entry.coord] = entry.metadata
    end
    return result
end

return Presets
