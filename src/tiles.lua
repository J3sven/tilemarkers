local MAP_SQUARE_SIZE = 64
local STORAGE_KEY = "tiles"
local STORAGE_VERSION = 2
local Styles = require("src/styles")

local storedData = PersistentDB:GetStructuredData(STORAGE_KEY)
local storedVersion = type(storedData) == "table"
    and tonumber(storedData.version)
    or nil
local loadedTiles = storedVersion == STORAGE_VERSION
    and storedData.levels
    or storedData

local function normalizeMetadata(metadata)
    local style = Styles.normalize(metadata)
    local normalized = {
        outlineColour = style.outlineColour,
        fillColour = style.fillColour,
        fill = style.fill,
        outlineCornersOnly = style.outlineCornersOnly,
        outlineThickness = style.outlineThickness,
    }
    if type(metadata) == "table"
        and type(metadata.text) == "string"
        and metadata.text ~= "" then
        normalized.text = metadata.text
    end
    return normalized
end

local function normalizeTiles(tiles)
    local normalized = {}
    for level, levelBucket in pairs(type(tiles) == "table" and tiles or {}) do
        if type(levelBucket) == "table" then
            local normalizedLevel = {}
            normalized[tonumber(level) or level] = normalizedLevel
            for squareKeyValue, square in pairs(levelBucket) do
                if type(square) == "table" then
                    local normalizedSquare = {}
                    normalizedLevel[tonumber(squareKeyValue) or squareKeyValue]
                        = normalizedSquare
                    for packed, metadata in pairs(square) do
                        normalizedSquare[tonumber(packed) or packed]
                            = normalizeMetadata(metadata)
                    end
                end
            end
        end
    end
    return normalized
end

local Tiles = {
    revision = 0,
    tiles = normalizeTiles(loadedTiles),
    customizationPreview = nil,
}

local function storageMetadata(metadata)
    local normalized = normalizeMetadata(metadata)
    return {
        text = normalized.text,
        outlineColour = Styles.encodeColour(normalized.outlineColour),
        fillColour = Styles.encodeColour(normalized.fillColour),
        fill = normalized.fill,
        outlineCornersOnly = normalized.outlineCornersOnly,
        outlineThickness = normalized.outlineThickness,
    }
end

local function storageData(tiles)
    local levels = {}
    for level, levelBucket in pairs(tiles) do
        local storedLevel = {}
        levels[level] = storedLevel
        for squareKeyValue, square in pairs(levelBucket) do
            local storedSquare = {}
            storedLevel[squareKeyValue] = storedSquare
            for packed, metadata in pairs(square) do
                storedSquare[packed] = storageMetadata(metadata)
            end
        end
    end
    return {
        version = STORAGE_VERSION,
        levels = levels,
    }
end

local function squareKey(coord)
    return (coord.mapSquareX << 8) | coord.mapSquareZ
end

local function coordKey(coord)
    return string.format(
        "%d:%d:%d",
        coord.level,
        squareKey(coord),
        coord:ToPacked())
end

function Tiles:save()
    self.revision = self.revision + 1
    return PersistentDB:SetStructuredData(STORAGE_KEY, storageData(self.tiles))
end

function Tiles:clear()
    local previousTiles = self.tiles
    self.tiles = {}
    if self:save() then
        return true
    end
    self.tiles = previousTiles
    return false
end

function Tiles:add(coord, metadata)
    local levelBucket = self.tiles[coord.level]
    if levelBucket == nil then
        levelBucket = {}
        self.tiles[coord.level] = levelBucket
    end

    local key = squareKey(coord)
    local square = levelBucket[key]
    if square == nil then
        square = {}
        levelBucket[key] = square
    end

    square[coord:ToPacked()] = normalizeMetadata(metadata)
    self:save()
end

function Tiles:remove(coord)
    local levelBucket = self.tiles[coord.level]
    if levelBucket == nil then
        return false
    end

    local square = levelBucket[squareKey(coord)]
    if square == nil or square[coord:ToPacked()] == nil then
        return false
    end

    square[coord:ToPacked()] = nil
    self:save()
    return true
end

function Tiles:removeAll(coords)
    local removed = {}
    for _, coord in ipairs(coords or {}) do
        local levelBucket = self.tiles[coord.level]
        local key = squareKey(coord)
        local square = levelBucket and levelBucket[key] or nil
        local packed = coord:ToPacked()
        local metadata = square and square[packed] or nil
        if metadata ~= nil then
            removed[#removed + 1] = {
                level = coord.level,
                squareKey = key,
                packed = packed,
                metadata = metadata,
            }
            square[packed] = nil
        end
    end

    if #removed == 0 then return true, 0 end
    if self:save() then return true, #removed end

    for _, entry in ipairs(removed) do
        self.tiles[entry.level][entry.squareKey][entry.packed] = entry.metadata
    end
    return false, 0
end

function Tiles:toggle(coord, metadata)
    if self:remove(coord) then
        return false
    end

    self:add(coord, metadata)
    return true
end

local function metadataAt(tiles, coord)
    local levelBucket = tiles[coord.level]
    if levelBucket == nil then return nil end
    local square = levelBucket[squareKey(coord)]
    return square and square[coord:ToPacked()] or nil
end

local function displayedMetadataAt(self, coord)
    local preview = self.customizationPreview
    if preview ~= nil and preview.key == coordKey(coord) then
        return preview.metadata
    end
    return metadataAt(self.tiles, coord)
end

local function applyCustomization(metadata, label, colour, fill, outlineCornersOnly)
    local style = Styles.fromColour(colour, fill, outlineCornersOnly)
    metadata.outlineColour = style.outlineColour
    metadata.fillColour = style.fillColour
    metadata.fill = style.fill
    metadata.outlineCornersOnly = style.outlineCornersOnly
    metadata.text = type(label) == "string" and label ~= "" and label or nil
end

function Tiles:contains(coord)
    return metadataAt(self.tiles, coord) ~= nil
end

function Tiles:getLabel(coord)
    local metadata = displayedMetadataAt(self, coord)
    return metadata and metadata.text or nil
end

function Tiles:getColour(coord)
    local metadata = displayedMetadataAt(self, coord)
    return metadata and metadata.outlineColour or nil
end

function Tiles:getFill(coord)
    local metadata = displayedMetadataAt(self, coord)
    if metadata == nil then return nil end
    return metadata.fill
end

function Tiles:getOutlineCornersOnly(coord)
    local metadata = displayedMetadataAt(self, coord)
    if metadata == nil then return nil end
    return metadata.outlineCornersOnly
end

function Tiles:setColour(coord, colour, fill, outlineCornersOnly)
    local metadata = metadataAt(self.tiles, coord)
    if metadata == nil then return false end

    local style = Styles.fromColour(colour, fill, outlineCornersOnly)
    metadata.outlineColour = style.outlineColour
    metadata.fillColour = style.fillColour
    metadata.fill = style.fill
    metadata.outlineCornersOnly = style.outlineCornersOnly
    return self:save()
end

function Tiles:previewCustomization(coord, label, colour, fill, outlineCornersOnly)
    local metadata = metadataAt(self.tiles, coord)
    if metadata == nil then return false end

    local preview = normalizeMetadata(metadata)
    applyCustomization(preview, label, colour, fill, outlineCornersOnly)
    preview.customizing = true
    self.customizationPreview = {
        key = coordKey(coord),
        metadata = preview,
    }
    self.revision = self.revision + 1
    return true
end

function Tiles:cancelCustomizationPreview(coord)
    local preview = self.customizationPreview
    if preview == nil or preview.key ~= coordKey(coord) then return false end
    self.customizationPreview = nil
    self.revision = self.revision + 1
    return true
end

function Tiles:setCustomization(coord, label, colour, fill, outlineCornersOnly)
    local metadata = metadataAt(self.tiles, coord)
    if metadata == nil then return false end

    applyCustomization(metadata, label, colour, fill, outlineCornersOnly)
    self:cancelCustomizationPreview(coord)
    return self:save()
end

function Tiles:setLabel(coord, label)
    local metadata = metadataAt(self.tiles, coord)
    if metadata == nil then return false end

    if type(label) == "string" and label ~= "" then
        metadata.text = label
    else
        metadata.text = nil
    end
    return self:save()
end

function Tiles:query(from, range, regionBindings)
    local results = {}
    if regionBindings ~= nil then
        for _, binding in ipairs(regionBindings) do
            local metadata = displayedMetadataAt(self, binding.source)
            if metadata ~= nil then
                results[binding.target] = metadata
            end
        end
        return results
    end

    local levelBucket = self.tiles[from.level]
    if levelBucket == nil then
        return results
    end

    local mapXMin = (from.x - range) // MAP_SQUARE_SIZE
    local mapXMax = (from.x + range) // MAP_SQUARE_SIZE
    local mapZMin = (from.z - range) // MAP_SQUARE_SIZE
    local mapZMax = (from.z + range) // MAP_SQUARE_SIZE

    for mapX = mapXMin, mapXMax do
        for mapZ = mapZMin, mapZMax do
            local centre = CoordGrid.new(0, mapX, mapZ, 32, 32)
            local square = levelBucket[squareKey(centre)]
            if square ~= nil then
                for packed, metadata in pairs(square) do
                    local coord = CoordGrid.new(packed)
                    if math.abs(coord.x - from.x) <= range
                        and math.abs(coord.z - from.z) <= range then
                        results[coord] = displayedMetadataAt(self, coord) or metadata
                    end
                end
            end
        end
    end

    return results
end

local function exportTile(coord, metadata)
    local tile = {
        x = coord.x,
        z = coord.z,
        level = coord.level,
    }
    if metadata ~= nil
        and type(metadata.text) == "string"
        and metadata.text ~= "" then
        tile.label = metadata.text
    end
    local style = Styles.normalize(metadata)
    tile.outlineColour = style.outlineColour
    tile.fillColour = style.fillColour
    tile.fill = style.fill
    tile.outlineThickness = style.outlineThickness
    tile.outlineCornersOnly = style.outlineCornersOnly
    return tile
end

function Tiles:export()
    local exported = {}
    for _, levelBucket in pairs(self.tiles) do
        for _, square in pairs(levelBucket) do
            for packed, metadata in pairs(square) do
                exported[#exported + 1] = exportTile(
                    CoordGrid.new(packed),
                    metadata)
            end
        end
    end
    return exported
end

function Tiles:exportCoords(coords)
    local exported = {}
    local seen = {}
    for _, coord in ipairs(coords or {}) do
        local packed = coord:ToPacked()
        if not seen[packed] then
            local metadata = metadataAt(self.tiles, coord)
            if metadata ~= nil then
                exported[#exported + 1] = exportTile(coord, metadata)
                seen[packed] = true
            end
        end
    end
    return exported
end

if storedData ~= nil and storedVersion ~= STORAGE_VERSION then
    Tiles:save()
end

return Tiles
