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
local frame = 0
local shapes = {}
local previousTiles = {}
local currentTiles = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function destroy(shape)
    if shape ~= nil then pcall(function() shape:Destroy() end) end
end

local function setShape(key, signature, shapeData, properties)
    local entry = shapes[key]
    if entry == nil then
        serial = serial + 1
        entry = {
            shape = ShapeList.CreateEntity(string.format(
                "tilemarkers_tile_%d", serial)),
        }
        if entry.shape == nil then return false, "failed to create shape" end
        shapes[key] = entry
    end

    if signature == nil or entry.signature ~= signature then
        if not entry.shape:SetShapeData(shapeData) then
            destroy(entry.shape)
            shapes[key] = nil
            return false, "failed to assign shape data"
        end
        entry.signature = signature
    end

    entry.shape.ignoreDepth = properties.ignoreDepth
    entry.shape.lineWidth = properties.lineWidth
    entry.shape.colour = 0xFFFFFFFF
    entry.shape.coordGrid = properties.coordGrid
    entry.lastSeen = frame
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

local function sidePosition(side, minX, minZ, inset, distance, level)
    local data = SIDES[side]
    local worldX = data.alongX
        and minX + distance
        or (side == "west" and minX or minX + TILE_SIZE)
    local worldZ = data.alongX
        and (side == "south" and minZ or minZ + TILE_SIZE)
        or minZ + distance
    worldX = math.floor(worldX + data.inwardX * inset + 0.5)
    worldZ = math.floor(worldZ + data.inwardZ * inset + 0.5)
    local height, available = World.GetGroundHeight(level, worldX, worldZ)
    if not available then return nil end
    return Vector3.new(
        worldX,
        height + HEIGHT_OFFSET + OUTLINE_HEIGHT_BIAS,
        worldZ)
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

local function addSide(buffers, side, minX, minZ, inset, level, colour)
    local from = sidePosition(side, minX, minZ, inset, 0.0, level)
    local to = sidePosition(side, minX, minZ, inset, TILE_SIZE, level)
    if from == nil or to == nil then return false end
    addLine(buffers, from, to, colour)
    return true
end

local function addCorners(buffers, side, minX, minZ, inset, level, colour)
    local cornerLength = TILE_SIZE * OUTLINE_CORNER_FRACTION
    local positions = {
        sidePosition(side, minX, minZ, inset, 0.0, level),
        sidePosition(side, minX, minZ, inset, cornerLength, level),
        sidePosition(side, minX, minZ, inset, TILE_SIZE - cornerLength, level),
        sidePosition(side, minX, minZ, inset, TILE_SIZE, level),
    }
    for index = 1, 4 do
        if positions[index] == nil then return false end
    end
    addLine(buffers, positions[1], positions[2], colour)
    addLine(buffers, positions[3], positions[4], colour)
    return true
end

local function projectedInset(side, minX, minZ, level, lineWidth)
    local data = SIDES[side]
    local midpointX = data.alongX
        and minX + HALF_TILE
        or (side == "west" and minX or minX + TILE_SIZE)
    local midpointZ = data.alongX
        and (side == "south" and minZ or minZ + TILE_SIZE)
        or minZ + HALF_TILE
    local startX = midpointX - (data.alongX and OUTLINE_INSET_PROBE or 0.0)
    local startZ = midpointZ - (data.alongX and 0.0 or OUTLINE_INSET_PROBE)
    local endX = midpointX + (data.alongX and OUTLINE_INSET_PROBE or 0.0)
    local endZ = midpointZ + (data.alongX and 0.0 or OUTLINE_INSET_PROBE)

    local function projected(x, z)
        local height, available = World.GetGroundHeight(level, x, z)
        if not available then return nil end
        local success, screenPosition = pcall(function()
            return ScreenConvert.Vector3ToScreen(Vector3.new(
                x, height + HEIGHT_OFFSET + OUTLINE_HEIGHT_BIAS, z))
        end)
        return success and screenPosition or nil
    end

    local startScreen = projected(startX, startZ)
    local endScreen = projected(endX, endZ)
    local midpointScreen = projected(midpointX, midpointZ)
    local inwardScreen = projected(
        midpointX + data.inwardX * OUTLINE_INSET_PROBE,
        midpointZ + data.inwardZ * OUTLINE_INSET_PROBE)
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

local function neighbouringOutline(level, x, z)
    local key = tileKey(level, x, z)
    local value = currentTiles[key]
    if value == nil then value = previousTiles[key] end
    return value ~= false and value or nil
end

local function splitOutlineSides(level, tileX, tileZ, outlineRGBA)
    if outlineRGBA == nil then return nil end
    local splitSides = {}
    for side, offset in pairs(NEIGHBOURS) do
        local neighbour = neighbouringOutline(
            level, tileX + offset.x, tileZ + offset.z)
        if neighbour ~= nil and neighbour ~= outlineRGBA then
            splitSides[side] = true
        end
    end
    return next(splitSides) ~= nil and splitSides or nil
end

local function buildMainShape(
    minX, minZ, level, outlineRGBA, fillRGBA, splitSides, cornersOnly)
    local grid = {}
    for z = 0, 1 do
        for x = 0, 1 do
            local worldX = minX + x * TILE_SIZE
            local worldZ = minZ + z * TILE_SIZE
            local height, available = World.GetGroundHeight(level, worldX, worldZ)
            if not available then return nil, "ground height is unavailable" end
            grid[#grid + 1] = Vector3.new(worldX, height + HEIGHT_OFFSET, worldZ)
        end
    end

    local buffers = { positions = {}, rgba = {}, lines = {}, tris = {} }
    if outlineRGBA ~= nil then
        if cornersOnly then
            for _, side in ipairs(SIDE_ORDER) do
                if splitSides == nil or splitSides[side] ~= true then
                    if not addCorners(
                            buffers, side, minX, minZ, 0.0, level, outlineRGBA) then
                        return nil, "ground height is unavailable"
                    end
                end
            end
        elseif splitSides == nil then
            local perimeter = { grid[1], grid[2], grid[4], grid[3] }
            for index, position in ipairs(perimeter) do
                buffers.positions[#buffers.positions + 1] = copyPosition(
                    position, OUTLINE_HEIGHT_BIAS)
                buffers.rgba[#buffers.rgba + 1] = outlineRGBA
                buffers.lines[#buffers.lines + 1] = index - 1
                buffers.lines[#buffers.lines + 1] = index % #perimeter
            end
        else
            for _, side in ipairs(SIDE_ORDER) do
                if splitSides[side] ~= true then
                    if not addSide(
                            buffers, side, minX, minZ, 0.0, level, outlineRGBA) then
                        return nil, "ground height is unavailable"
                    end
                end
            end
        end
    end

    if fillRGBA ~= nil then
        local offset = #buffers.positions
        for _, position in ipairs(grid) do
            buffers.positions[#buffers.positions + 1] = copyPosition(position)
            buffers.rgba[#buffers.rgba + 1] = fillRGBA
        end
        buffers.tris = {
            offset,
            offset + 1,
            offset + 3,
            offset,
            offset + 3,
            offset + 2,
        }
    end

    local shape = ShapeData.new()
    shape.positions = buffers.positions
    shape.rgba = buffers.rgba
    shape.lines = buffers.lines
    shape.tris = buffers.tris
    return shape
end

local function buildSplitShape(
    minX, minZ, level, outlineRGBA, splitSides, lineWidth, cornersOnly)
    if outlineRGBA == nil or splitSides == nil then return nil end

    local buffers = { positions = {}, rgba = {}, lines = {} }
    for _, side in ipairs(SIDE_ORDER) do
        if splitSides[side] == true then
            local inset = projectedInset(side, minX, minZ, level, lineWidth)
            local added
            if cornersOnly then
                added = addCorners(
                    buffers, side, minX, minZ, inset, level, outlineRGBA)
            else
                added = addSide(
                    buffers, side, minX, minZ, inset, level, outlineRGBA)
            end
            if not added then return nil, "ground height is unavailable" end
        end
    end
    if #buffers.lines == 0 then return nil end

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

local function splitSignature(splitSides)
    if splitSides == nil then return "" end
    local parts = {}
    for _, side in ipairs(SIDE_ORDER) do
        if splitSides[side] then parts[#parts + 1] = side end
    end
    return table.concat(parts, ",")
end

function Draw.BeginFrame()
    previousTiles = currentTiles
    currentTiles = {}

    local stale = {}
    for key, entry in pairs(shapes) do
        if entry.lastSeen < frame then stale[#stale + 1] = key end
    end
    for _, key in ipairs(stale) do
        destroy(shapes[key].shape)
        shapes[key] = nil
    end
    frame = frame + 1
end

function Draw.Reset()
    previousTiles = {}
    currentTiles = {}
    for _, entry in pairs(shapes) do destroy(entry.shape) end
    shapes = {}
    frame = 0
end

function Draw.Tile(settings)
    settings = settings or {}
    local coord = settings.coordGrid
    if coord == nil then return false, "coordGrid is required" end

    local outlineEnabled = settings.outline ~= false
    local fillEnabled = settings.fill == true
        or (settings.fill == nil and settings.fillColour ~= nil)
    if not outlineEnabled and not fillEnabled then
        return false, "outline and fill are both disabled"
    end

    local outlineRGB, outlineAlpha = splitColour(
        settings.outlineColour or settings.colour,
        0xFFFFFFFF,
        settings.outlineOpacity or settings.opacity,
        1.0)
    local fillRGB, fillAlpha = splitColour(
        settings.fillColour or outlineRGB,
        outlineRGB,
        settings.fillOpacity,
        DEFAULT_FILL_OPACITY)
    local outlineRGBA = outlineEnabled and ((outlineRGB << 8) | outlineAlpha) or nil
    local fillRGBA = fillEnabled and ((fillRGB << 8) | fillAlpha) or nil
    local cornersOnly = settings.outlineCornersOnly == true
        or settings.cornersOnly == true
    local lineWidth = clamp(
        tonumber(settings.outlineThickness)
            or tonumber(settings.lineWidth)
            or DEFAULT_LINE_WIDTH,
        0.0,
        10.0)

    local centre = coord:ToCoordFine(true).position
    local level = coord.level
    local minX, minZ, tileX, tileZ = tilePosition(centre)
    local splitSides = splitOutlineSides(
        level, tileX, tileZ, outlineRGBA)
    local shape, shapeError = buildMainShape(
        minX,
        minZ,
        level,
        outlineRGBA,
        fillRGBA,
        splitSides,
        cornersOnly)
    if shape == nil then return false, shapeError end

    local splitShape, splitError = buildSplitShape(
        minX,
        minZ,
        level,
        outlineRGBA,
        splitSides,
        lineWidth,
        cornersOnly)
    if splitError ~= nil then return false, splitError end

    local anchorHeight, available = World.GetGroundHeight(level, centre.x, centre.z)
    if not available then return false, "ground height is unavailable" end
    local anchor = Vector3.new(centre.x, anchorHeight, centre.z)
    localiseShape(shape, anchor)
    if splitShape ~= nil then localiseShape(splitShape, anchor) end

    local key = tostring(settings.id or string.format(
        "fixed:%d:%d:%d", level, centre.x, centre.z))
    local signature = table.concat({
        level,
        tileX,
        tileZ,
        outlineRGBA or "none",
        fillRGBA or "none",
        cornersOnly and 1 or 0,
        splitSignature(splitSides),
    }, ":")
    local properties = {
        coordGrid = coord,
        ignoreDepth = settings.ignoreDepth == true,
        lineWidth = lineWidth,
    }
    local drawn, drawError = setShape(
        key .. ":main", signature, shape, properties)
    if not drawn then return false, drawError end

    if splitShape ~= nil then
        properties.lineWidth = lineWidth * 0.5
        drawn, drawError = setShape(
            key .. ":split", nil, splitShape, properties)
        if not drawn then return false, drawError end
    end

    currentTiles[tileKey(level, tileX, tileZ)] = outlineRGBA or false
    return true
end

return Draw
