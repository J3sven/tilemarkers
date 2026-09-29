local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 0.001,
        message .. ": expected " .. expected .. ", got " .. actual)
end

Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }
ShapeData = { new = function() return {} end }
local submitted = {}
local function create()
    local shape = {
        SetShapeData = function(self, data) self.data = data; return true end,
        Destroy = function(self) self.destroyed = true; return true end,
    }
    submitted[#submitted + 1] = shape
    return shape
end
ShapeList = { CreateEntity = create, CreateInstance = create }
ScreenConvert = {
    Vector3ToScreen = function(p) return { x = p.x / 16, y = (p.z - p.y) / 16 } end,
}

local preset = assert(require("src/preset_codec").decode(
    "TM2AQpicmlkZ2UgYnVnAdoytDIBhc8-_2qmMowMFAA"))
local tile = preset.tiles[1]
local minX, minZ = tile.x * 512, tile.z * 512
local function coord(level, x, z)
    return {
        level = level,
        ToCoordFine = function()
            return { position = Vector3.new(x + 256, 0, z + 256) }
        end,
    }
end

-- A sloping deck ends at the north/east tile boundaries. Sampling the
-- neighbouring tile returns the floor below, not this deck's corner height.
local deckHeight, slope = 2400, 1
World = {
    GetGroundHeight = function(level, x, z)
        if x >= minX and x < minX + 512 and z >= minZ and z < minZ + 512 then
            return deckHeight + level * 800 + (x - minX) * slope + (z - minZ), true
        end
        return 100 + level * 800, true
    end,
}
local Draw = require("src/draw")
local function verifyDeck(shape, level)
    -- Entity placement is deliberately independent of the height sampler:
    -- implicit placement cannot guarantee which linked surface is selected.
    local anchor = shape.translation or Vector3.new(minX + 256, 100 + level * 800, minZ + 256)
    for index, p in ipairs(shape.data.positions) do
        local x, z = p.x + anchor.x, p.z + anchor.z
        assert(x >= minX and x <= minX + 512, "marker stays within tile X bounds")
        assert(z >= minZ and z <= minZ + 512, "marker stays within tile Z bounds")
        local height = deckHeight + level * 800
            + math.min(x - minX, 511) * slope + math.min(z - minZ, 511)
        local bias = (#shape.data.tris > 0 and shape.data.rgba[index] == 0x1122338C) and 30 or 31
        near(p.y + anchor.y, height + bias, "vertex follows marked surface")
    end
end

for level = 0, 3 do
    for _, cornersOnly in ipairs({ false, true }) do
        Draw.Reset()
        submitted = {}
        local settings = {
            coordGrid = coord(level, minX, minZ),
            outlineColour = 0x112233, fill = true, outlineCornersOnly = cornersOnly,
        }
        assert(Draw.Tile(settings))
        verifyDeck(submitted[1], level)

        -- Changing the loaded terrain must replace cached local mesh heights.
        slope = 2
        assert(Draw.Tile(settings))
        verifyDeck(submitted[1], level)
        slope = 1

        -- Both split edges and their projection probes must stay on the deck.
        assert(Draw.Tile{ coordGrid = coord(level, minX + 512, minZ), colour = 0xAABBCC })
        assert(Draw.Tile{ coordGrid = coord(level, minX, minZ + 512), colour = 0xAABBCC })
        Draw.BeginFrame()
        local firstSplit = #submitted + 1
        assert(Draw.Tile(settings))
        verifyDeck(submitted[1], level)
        verifyDeck(submitted[firstSplit], level)
    end
end
Draw.Reset()
submitted = {}
World.GetGroundHeight = function(level) return 100 + level * 800, true end
for level = 0, 3 do
    assert(Draw.Tile{ coordGrid = coord(level, minX, minZ) })
    local shape = submitted[#submitted]
    for _, p in ipairs(shape.data.positions) do
        near(p.y + shape.translation.y, 131 + level * 800, "ordinary floor keeps its level")
    end
end
Draw.Reset()
submitted = {}
World.GetGroundHeight = function() return -1, false end
local drawn, message = Draw.Tile{ coordGrid = coord(0, minX, minZ) }
assert(not drawn and message == "ground height is unavailable")
assert(#submitted == 0, "unavailable terrain must not produce a marker")
print("test_draw_height: ok")
