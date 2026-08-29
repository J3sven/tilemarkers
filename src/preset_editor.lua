local Styles = require("src/styles")

local Editor = {
    presetID = nil,
    presetName = nil,
    tiles = {},
}

local function keyFor(level, x, z)
    return string.format("%d:%d:%d", level, x, z)
end

local function coordKey(coord)
    return keyFor(coord.level, coord.x, coord.z)
end

local function copyTile(tile)
    local style = Styles.normalize(tile)
    return {
        x = math.floor(tonumber(tile.x) or 0),
        z = math.floor(tonumber(tile.z) or 0),
        level = math.floor(tonumber(tile.level) or 0),
        label = type(tile.label or tile.text) == "string"
            and (tile.label or tile.text)
            or nil,
        outlineColour = style.outlineColour,
        fillColour = style.fillColour,
        fill = style.fill,
        outlineCornersOnly = style.outlineCornersOnly,
        outlineThickness = style.outlineThickness,
    }
end

local function metadataFor(tile)
    return {
        text = tile.label,
        outlineColour = tile.outlineColour,
        fillColour = tile.fillColour,
        fill = tile.fill,
        outlineCornersOnly = tile.outlineCornersOnly,
        outlineThickness = tile.outlineThickness,
    }
end

function Editor:isActive()
    return self.presetID ~= nil
end

function Editor:begin(preset)
    if self:isActive() or type(preset) ~= "table" then
        return false
    end
    self.presetID = preset.id
    self.presetName = preset.name
    self.tiles = {}
    for _, tile in ipairs(type(preset.tiles) == "table" and preset.tiles or {}) do
        local copied = copyTile(tile)
        self.tiles[keyFor(copied.level, copied.x, copied.z)] = copied
    end
    return true
end

function Editor:cancel()
    self.presetID = nil
    self.presetName = nil
    self.tiles = {}
end

function Editor:contains(coord)
    return self:isActive() and self.tiles[coordKey(coord)] ~= nil
end

function Editor:add(coord, metadata)
    if not self:isActive() then return false end
    local tile = copyTile({
        x = coord.x,
        z = coord.z,
        level = coord.level,
        text = metadata and metadata.text,
        outlineColour = metadata and metadata.outlineColour,
        fillColour = metadata and metadata.fillColour,
        fill = metadata and metadata.fill,
        outlineCornersOnly = metadata and metadata.outlineCornersOnly,
        outlineThickness = metadata and metadata.outlineThickness,
    })
    self.tiles[coordKey(coord)] = tile
    return true
end

function Editor:remove(coord)
    if not self:contains(coord) then return false end
    self.tiles[coordKey(coord)] = nil
    return true
end

function Editor:getLabel(coord)
    local tile = self.tiles[coordKey(coord)]
    return tile and tile.label or nil
end

function Editor:getColour(coord)
    local tile = self.tiles[coordKey(coord)]
    return tile and tile.outlineColour or nil
end

function Editor:getFill(coord)
    local tile = self.tiles[coordKey(coord)]
    if tile == nil then return nil end
    return tile.fill
end

function Editor:getOutlineCornersOnly(coord)
    local tile = self.tiles[coordKey(coord)]
    if tile == nil then return nil end
    return tile.outlineCornersOnly
end

function Editor:setCustomization(coord, label, colour, fill, outlineCornersOnly)
    local tile = self.tiles[coordKey(coord)]
    if tile == nil then return false end
    local style = Styles.fromColour(colour, fill, outlineCornersOnly)
    tile.label = type(label) == "string" and label ~= "" and label or nil
    tile.outlineColour = style.outlineColour
    tile.fillColour = style.fillColour
    tile.fill = style.fill
    tile.outlineCornersOnly = style.outlineCornersOnly
    return true
end

function Editor:export()
    local result = {}
    for _, tile in pairs(self.tiles) do
        result[#result + 1] = copyTile(tile)
    end
    table.sort(result, function(left, right)
        if left.level ~= right.level then return left.level < right.level end
        if left.x ~= right.x then return left.x < right.x end
        return left.z < right.z
    end)
    return result
end

function Editor:query(from, range, regionBindings)
    local result = {}
    if not self:isActive() then return result end

    if regionBindings ~= nil then
        for _, binding in ipairs(regionBindings) do
            local tile = self.tiles[coordKey(binding.source)]
            if tile ~= nil then result[binding.target] = metadataFor(tile) end
        end
        return result
    end

    for _, tile in pairs(self.tiles) do
        if tile.level == from.level
            and math.abs(tile.x - from.x) <= range
            and math.abs(tile.z - from.z) <= range then
            local coord = CoordGrid.new(
                tile.level,
                tile.x // 64,
                tile.z // 64,
                tile.x % 64,
                tile.z % 64)
            result[coord] = metadataFor(tile)
        end
    end
    return result
end

return Editor
