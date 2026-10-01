local Draw = {}

local TILE_SIZE = 512.0
local HALF_TILE = TILE_SIZE * 0.5
local OUTLINE_HEIGHT_BIAS = 1.0
local HEIGHT_OFFSET = 30.0
local DEFAULT_FILL_OPACITY = 0.55
local DEFAULT_LINE_WIDTH = 2.0
local OUTLINE_INSET_PROBE = 64.0
local MAX_OUTLINE_INSET = HALF_TILE - 1.0
local OUTLINE_CORNER_FRACTION = 0.25
local SIDES = {
    south = { alongX = true, inwardX = 0.0, inwardZ = 1.0 },
    north = { alongX = true, inwardX = 0.0, inwardZ = -1.0 },
    west = { alongX = false, inwardX = 1.0, inwardZ = 0.0 },
    east = { alongX = false, inwardX = -1.0, inwardZ = 0.0 },
}
local SIDE_ORDER = { "south", "north", "west", "east" }
local NEIGHBOURS = {
    south = { x = 0, z = -1 },
    north = { x = 0, z = 1 },
    west = { x = -1, z = 0 },
    east = { x = 1, z = 0 },
}

local serial = 0
local tiles = {}
local splitTiles = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function destroy(shape)
    if shape ~= nil then pcall(function() shape:Destroy() end) end
end

local function removeShape(entry, part)
    local retained = entry[part]
    if retained ~= nil then destroy(retained.shape) end
    entry[part] = nil
    entry[part .. "Signature"] = nil
end

local function applyProperties(retained, style, lineWidth)
    if retained == nil then return end
    local shape = retained.shape
    if retained.ignoreDepth ~= style.ignoreDepth then
        shape.ignoreDepth = style.ignoreDepth
        retained.ignoreDepth = style.ignoreDepth
    end
    if retained.lineWidth ~= lineWidth then
        shape.lineWidth = lineWidth
        retained.lineWidth = lineWidth
    end
    if retained.drawDistance ~= style.drawDistance then
        shape:SetDrawDistance(style.drawDistance)
        retained.drawDistance = style.drawDistance
    end
end

local function setShape(entry, part, shapeData)
    if shapeData == false then
        removeShape(entry, part)
        return true
    end
    local retained = entry[part]
    if retained == nil then
        serial = serial + 1
        local shape = ShapeList.CreateEntity(string.format("tilemarkers_tile_%d", serial))
        if shape == nil then return false end
        retained = { shape = shape }
        entry[part] = retained
        shape.alignType = ShapeEntityAlignType.NONE
        -- Changing this property rebuilds the native visual; a resident never moves.
        shape.coordGrid = entry.coordGrid
    end
    if not retained.shape:SetShapeData(shapeData) then
        removeShape(entry, part)
        return false
    end
    return true
end

local function alphaByte(opacity)
    return math.floor(clamp(tonumber(opacity) or 1.0, 0.0, 1.0) * 255.0 + 0.5)
end

local function splitColour(colour, fallback, opacity, defaultOpacity)
    colour = math.floor(tonumber(colour) or fallback)
    local rgb
    local embeddedOpacity
    if colour > 0xFFFFFF then
        rgb = (colour >> 8) & 0xFFFFFF
        embeddedOpacity = (colour & 0xFF) / 255.0
    else
        rgb = colour & 0xFFFFFF
    end
    return rgb, alphaByte(opacity ~= nil and opacity or embeddedOpacity or defaultOpacity)
end

local function copyPosition(position, heightBias)
    return Vector3.new(position.x, position.y + (heightBias or 0.0), position.z)
end

local function tileKey(level, x, z)
    return string.format("%d:%d:%d", level, x, z)
end

local function tilePosition(centre)
    local minX = math.floor(centre.x - HALF_TILE + 0.5)
    local minZ = math.floor(centre.z - HALF_TILE + 0.5)
    return minX, minZ, math.floor(minX / TILE_SIZE), math.floor(minZ / TILE_SIZE)
end

local function tileHeight(entry, x, z)
    x = clamp(x, entry.minX, entry.minX + TILE_SIZE - 1)
    z = clamp(z, entry.minZ, entry.minZ + TILE_SIZE - 1)
    local key = (x - entry.minX) * TILE_SIZE + z - entry.minZ
    local height = entry.heights[key]
    if height == nil then
        local available
        height, available = World.GetGroundHeight(entry.level, x, z)
        if not available then return nil end
        entry.heights[key] = height
    end
    return height
end

local function ensureAnchor(entry)
    if entry.anchor ~= nil then return true end
    local x, z = entry.minX + HALF_TILE, entry.minZ + HALF_TILE
    local height = tileHeight(entry, x, z)
    if height == nil then return false end
    -- coordGrid is documented to anchor at the centre's ground height. The API
    -- does not expose its native height or specify linked bridge-plane selection;
    -- equivalence with this explicit centre sample needs in-client verification.
    entry.anchor = Vector3.new(x, height, z)
    return true
end

local function sidePosition(entry, side, inset, distance)
    local data = SIDES[side]
    local worldX = data.alongX
        and entry.minX + distance
        or (side == "west" and entry.minX or entry.minX + TILE_SIZE)
    local worldZ = data.alongX
        and (side == "south" and entry.minZ or entry.minZ + TILE_SIZE)
        or entry.minZ + distance
    worldX = math.floor(worldX + data.inwardX * inset + 0.5)
    worldZ = math.floor(worldZ + data.inwardZ * inset + 0.5)
    local height = tileHeight(entry, worldX, worldZ)
    if height == nil then return nil end
    return Vector3.new(worldX, height + HEIGHT_OFFSET + OUTLINE_HEIGHT_BIAS, worldZ)
end

local function addLine(buffers, from, to, colour)
    local offset = #buffers.positions
    buffers.positions[#buffers.positions + 1] = from
    buffers.positions[#buffers.positions + 1] = to
    buffers.rgba[#buffers.rgba + 1] = colour
    buffers.rgba[#buffers.rgba + 1] = colour
    buffers.lines[#buffers.lines + 1] = offset
    buffers.lines[#buffers.lines + 1] = offset + 1
end

local function addSide(buffers, entry, side, inset, colour)
    local from = sidePosition(entry, side, inset, 0.0)
    local to = sidePosition(entry, side, inset, TILE_SIZE)
    if from == nil or to == nil then return false end
    addLine(buffers, from, to, colour)
    return true
end

local function addCorners(buffers, entry, side, inset, colour)
    local cornerLength = TILE_SIZE * OUTLINE_CORNER_FRACTION
    local positions = {
        sidePosition(entry, side, inset, 0.0),
        sidePosition(entry, side, inset, cornerLength),
        sidePosition(entry, side, inset, TILE_SIZE - cornerLength),
        sidePosition(entry, side, inset, TILE_SIZE),
    }
    for index = 1, 4 do
        if positions[index] == nil then return false end
    end
    addLine(buffers, positions[1], positions[2], colour)
    addLine(buffers, positions[3], positions[4], colour)
    return true
end

local function projectedInset(entry, side, lineWidth)
    local probes = entry.probes[side]
    if probes == nil then
        local data = SIDES[side]
        local midpointX = data.alongX
            and entry.minX + HALF_TILE
            or (side == "west" and entry.minX or entry.minX + TILE_SIZE)
        local midpointZ = data.alongX
            and (side == "south" and entry.minZ or entry.minZ + TILE_SIZE)
            or entry.minZ + HALF_TILE
        local function probe(x, z)
            local height = tileHeight(entry, x, z)
            if height == nil then return nil end
            return Vector3.new(x, height + HEIGHT_OFFSET + OUTLINE_HEIGHT_BIAS, z)
        end
        probes = {
            probe(midpointX - (data.alongX and OUTLINE_INSET_PROBE or 0.0),
                midpointZ - (data.alongX and 0.0 or OUTLINE_INSET_PROBE)),
            probe(midpointX + (data.alongX and OUTLINE_INSET_PROBE or 0.0),
                midpointZ + (data.alongX and 0.0 or OUTLINE_INSET_PROBE)),
            probe(midpointX, midpointZ),
            probe(midpointX + data.inwardX * OUTLINE_INSET_PROBE,
                midpointZ + data.inwardZ * OUTLINE_INSET_PROBE),
        }
        for index = 1, 4 do
            if probes[index] == nil then return nil end
        end
        entry.probes[side] = probes
    end
    local function projected(position)
        local success, screen = pcall(ScreenConvert.Vector3ToScreen, position)
        return success and screen or nil
    end
    local startScreen = projected(probes[1])
    local endScreen = projected(probes[2])
    local midpointScreen = projected(probes[3])
    local inwardScreen = projected(probes[4])
    if startScreen == nil or endScreen == nil
        or midpointScreen == nil or inwardScreen == nil then
        return 1.0
    end

    local edgeX = endScreen.x - startScreen.x
    local edgeY = endScreen.y - startScreen.y
    local edgeLength = math.sqrt(edgeX * edgeX + edgeY * edgeY)
    if edgeLength < 0.001 then return 1.0 end

    local normalX = -edgeY / edgeLength
    local normalY = edgeX / edgeLength
    local inwardX = inwardScreen.x - midpointScreen.x
    local inwardY = inwardScreen.y - midpointScreen.y
    local perpendicularPixels = math.abs(inwardX * normalX + inwardY * normalY)
    if perpendicularPixels < 0.001 then return 1.0 end

    return clamp(
        lineWidth * 0.25 * OUTLINE_INSET_PROBE / perpendicularPixels,
        1.0,
        MAX_OUTLINE_INSET)
end

local function splitOutlineSides(entry, desired)
    local outline = entry.style.outlineRGBA
    local mask = 0
    if outline == nil then return mask end
    for index, side in ipairs(SIDE_ORDER) do
        local offset = NEIGHBOURS[side]
        local neighbour = desired[tileKey(
            entry.level, entry.tileX + offset.x, entry.tileZ + offset.z)]
        if neighbour ~= nil and neighbour.style.outlineRGBA ~= nil
            and neighbour.style.outlineRGBA ~= outline then
            mask = mask | (1 << (index - 1))
        end
    end
    return mask
end

local function isSplit(mask, index)
    return (mask & (1 << (index - 1))) ~= 0
end

local function buildMainShape(entry)
    local style, mask = entry.style, entry.mask
    if style.fillRGBA == nil and (style.outlineRGBA == nil or mask == 15) then
        -- A surrounded, unfilled tile has only split edges. Empty ShapeData is invalid.
        return false
    end
    local grid = {}
    for z = 0, 1 do
        for x = 0, 1 do
            local worldX = entry.minX + x * TILE_SIZE
            local worldZ = entry.minZ + z * TILE_SIZE
            local height = tileHeight(entry, worldX, worldZ)
            if height == nil then return nil end
            grid[#grid + 1] = Vector3.new(worldX, height + HEIGHT_OFFSET, worldZ)
        end
    end

    local buffers = { positions = {}, rgba = {}, lines = {}, tris = {} }
    if style.outlineRGBA ~= nil then
        if style.cornersOnly then
            for index, side in ipairs(SIDE_ORDER) do
                if not isSplit(mask, index)
                    and not addCorners(buffers, entry, side, 0.0, style.outlineRGBA) then
                    return nil
                end
            end
        elseif mask == 0 then
            local perimeter = { grid[1], grid[2], grid[4], grid[3] }
            for index, position in ipairs(perimeter) do
                buffers.positions[#buffers.positions + 1] = copyPosition(
                    position, OUTLINE_HEIGHT_BIAS)
                buffers.rgba[#buffers.rgba + 1] = style.outlineRGBA
                buffers.lines[#buffers.lines + 1] = index - 1
                buffers.lines[#buffers.lines + 1] = index % #perimeter
            end
        else
            for index, side in ipairs(SIDE_ORDER) do
                if not isSplit(mask, index)
                    and not addSide(buffers, entry, side, 0.0, style.outlineRGBA) then
                    return nil
                end
            end
        end
    end

    if style.fillRGBA ~= nil then
        local offset = #buffers.positions
        for _, position in ipairs(grid) do
            buffers.positions[#buffers.positions + 1] = copyPosition(position)
            buffers.rgba[#buffers.rgba + 1] = style.fillRGBA
        end
        buffers.tris = {
            offset, offset + 1, offset + 3,
            offset, offset + 3, offset + 2,
        }
    end

    local shape = ShapeData.new()
    shape.positions = buffers.positions
    shape.rgba = buffers.rgba
    shape.lines = buffers.lines
    shape.tris = buffers.tris
    return shape
end

local function buildSplitShape(entry, insets)
    local buffers = { positions = {}, rgba = {}, lines = {} }
    for index, side in ipairs(SIDE_ORDER) do
        if isSplit(entry.mask, index) then
            local added
            if entry.style.cornersOnly then
                added = addCorners(buffers, entry, side, insets[index], entry.style.outlineRGBA)
            else
                added = addSide(buffers, entry, side, insets[index], entry.style.outlineRGBA)
            end
            if not added then return nil end
        end
    end

    local shape = ShapeData.new()
    shape.positions = buffers.positions
    shape.rgba = buffers.rgba
    shape.lines = buffers.lines
    shape.tris = {}
    return shape
end

local function localiseShape(shape, anchor)
    for index, position in ipairs(shape.positions) do
        shape.positions[index] = Vector3.new(
            position.x - anchor.x,
            position.y - anchor.y,
            position.z - anchor.z)
    end
end

local function splitSignature(entry)
    return table.concat({
        entry.style.outlineRGBA or "none",
        entry.style.cornersOnly and 1 or 0,
        entry.mask,
    }, ":")
end

local function updateSplit(entry, signature)
    if not ensureAnchor(entry) then return false end
    local insets = {}
    local changed = entry.splitSignature ~= signature or entry.split == nil
    for index, side in ipairs(SIDE_ORDER) do
        if isSplit(entry.mask, index) then
            local inset = projectedInset(entry, side, entry.style.lineWidth)
            if inset == nil then return false end
            -- Mesh coordinates are rounded to fine units; sub-unit camera changes
            -- must not allocate another ShapeData or upload identical geometry.
            insets[index] = math.floor(inset + 0.5)
            if entry.insets == nil or entry.insets[index] ~= insets[index] then
                changed = true
            end
        end
    end
    if changed then
        local shape = buildSplitShape(entry, insets)
        if shape == nil then return false end
        localiseShape(shape, entry.anchor)
        if not setShape(entry, "split", shape) then return false end
        entry.insets = insets
        entry.splitSignature = signature
    end
    entry.projectedLineWidth = entry.style.lineWidth
    applyProperties(entry.split, entry.style, entry.style.lineWidth * 0.5)
    return true
end

local function normaliseStyle(settings)
    local outlineRGB, outlineAlpha = splitColour(
        settings.outlineColour, 0xFFFFFFFF, settings.outlineOpacity, 1.0)
    local fillRGB, fillAlpha = splitColour(
        settings.fillColour or outlineRGB, outlineRGB,
        settings.fillOpacity, DEFAULT_FILL_OPACITY)
    local fillEnabled = settings.fill == true
        or (settings.fill == nil and settings.fillColour ~= nil)
    return {
        outlineRGBA = settings.outline ~= false and ((outlineRGB << 8) | outlineAlpha) or nil,
        fillRGBA = fillEnabled and ((fillRGB << 8) | fillAlpha) or nil,
        cornersOnly = settings.outlineCornersOnly == true,
        lineWidth = clamp(tonumber(settings.outlineThickness) or DEFAULT_LINE_WIDTH, 0.0, 10.0),
        ignoreDepth = settings.ignoreDepth == true,
        drawDistance = tonumber(settings.drawDistance) or 24 * TILE_SIZE,
    }
end

local function reconcile(entry)
    if not ensureAnchor(entry) then return false end
    local style = entry.style
    local signature = table.concat({
        style.outlineRGBA or "none", style.fillRGBA or "none",
        style.cornersOnly and 1 or 0, entry.mask,
    }, ":")
    local ready = true
    if entry.mainSignature ~= signature then
        local shape = buildMainShape(entry)
        if shape == nil then
            ready = false
        else
            if shape ~= false then localiseShape(shape, entry.anchor) end
            if setShape(entry, "main", shape) then
                entry.mainSignature = signature
            else
                ready = false
            end
        end
    end
    applyProperties(entry.main, style, style.lineWidth)

    if entry.mask == 0 then
        removeShape(entry, "split")
        entry.insets = nil
        entry.projectedLineWidth = nil
    else
        local split = entry.splitTarget
        if entry.splitSignature ~= split or entry.projectedLineWidth ~= style.lineWidth then
            if not updateSplit(entry, split) then ready = false end
        else
            applyProperties(entry.split, style, style.lineWidth * 0.5)
        end
    end
    return ready
end

function Draw.Sync(settingsList)
    local desired = {}
    local ready = true
    for _, settings in ipairs(settingsList) do
        local coord = settings.coordGrid
        if coord == nil then
            ready = false
        else
            local centre = coord:ToCoordFine(true).position
            local minX, minZ, tileX, tileZ = tilePosition(centre)
            local key = tileKey(coord.level, tileX, tileZ)
            local entry = tiles[key]
            if entry == nil then
                entry = {
                    coordGrid = coord, level = coord.level,
                    minX = minX, minZ = minZ, tileX = tileX, tileZ = tileZ,
                    heights = {}, probes = {},
                }
            end
            entry.style = normaliseStyle(settings)
            desired[key] = entry
        end
    end
    for key, entry in pairs(tiles) do
        if desired[key] == nil then
            removeShape(entry, "main")
            removeShape(entry, "split")
        end
    end
    tiles = desired
    splitTiles = {}
    -- All desired outlines are known before either member of a shared edge builds.
    for key, entry in pairs(tiles) do
        entry.mask = splitOutlineSides(entry, desired)
        entry.splitTarget = splitSignature(entry)
        if entry.mask ~= 0 then splitTiles[key] = entry end
        if not reconcile(entry) then ready = false end
    end
    return ready
end

function Draw.UpdateCamera()
    for _, entry in pairs(splitTiles) do
        updateSplit(entry, entry.splitTarget)
    end
end

function Draw.Reset()
    for _, entry in pairs(tiles) do
        removeShape(entry, "main")
        removeShape(entry, "split")
    end
    tiles = {}
    splitTiles = {}
end

return Draw
