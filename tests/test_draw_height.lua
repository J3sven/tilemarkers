local function near(actual, expected, message)
    assert(math.abs(actual - expected) < 0.001,
        message .. ": expected " .. expected .. ", got " .. actual)
end

Vector3 = { new = function(x, y, z) return { x = x, y = y, z = z } end }
ShapeEntityAlignType = { NONE = 0, MODEL = 2 }
ShapeData = { new = function() return {} end }
local submitted, projected = {}, {}
ShapeList = { CreateEntity = function()
    local values = { alignType = ShapeEntityAlignType.NONE }
    local shape = setmetatable({}, {
        __index = values,
        __newindex = function(_, key, value)
            assert(key ~= "translation", "native entities have no translation transform")
            if key == "coordGrid" then
                assert(values.coordGrid == nil, "native anchor is assigned only once")
                local centre = value:ToCoordFine(true).position
                -- Documented model: coordGrid places an entity at the tile centre,
                -- automatically at ground height. The docs do NOT guarantee that
                -- native linked/bridge-plane selection equals GetGroundHeight on
                -- this level, nor expose the actual native anchor for comparison.
                -- This mock tests relative terrain geometry under that model. It
                -- cannot prove the native anchor on bridges; verify that in-client.
                local height, available = World.GetGroundHeight(value.level, centre.x, centre.z)
                assert(available, "entity is not created until terrain is available")
                values.anchor = Vector3.new(centre.x, height, centre.z)
            end
            values[key] = value
        end,
    })
    values.SetShapeData = function(_, data)
        assert(#data.positions > 0 and (#data.lines > 0 or #data.tris > 0))
        values.data = data
        return true
    end
    values.SetDrawDistance = function(_, distance) values.drawDistance = distance end
    values.Destroy = function() values.destroyed = true; return true end
    submitted[#submitted + 1] = shape
    return shape
end }
ScreenConvert = { Vector3ToScreen = function(p)
    projected[#projected + 1] = p
    return { x = p.x / 16, y = (p.z - p.y) / 16 }
end }

local preset = assert(require("src/preset_codec").decode(
    "TM2AQpicmlkZ2UgYnVnAdoytDIBhc8-_2qmMowMFAA"))
local tile = preset.tiles[1]
local minX, minZ = tile.x * 512, tile.z * 512
local function coord(level, x, z)
    return {
        level = level, x = x, z = z,
        ToCoordFine = function()
            return { position = Vector3.new(x + 256, 0, z + 256) }
        end,
    }
end

-- A sloping deck ends at the north/east tile boundaries. Sampling the
-- neighbouring tile returns the floor below, not this deck's corner height.
local deckHeight, slope, samples = 2400, 1, 0
local function ground(level, x, z)
    if x >= minX and x < minX + 512 and z >= minZ and z < minZ + 512 then
        return deckHeight + level * 800 + (x - minX) * slope + (z - minZ)
    end
    return 100 + level * 800
end
World = { GetGroundHeight = function(level, x, z)
    samples = samples + 1
    return ground(level, x, z), true
end }
package.loaded["src/draw"] = nil
local Draw = require("src/draw")
local function verifyDeck(shape, level)
    local anchor = shape.anchor
    for index, p in ipairs(shape.data.positions) do
        local x, z = p.x + anchor.x, p.z + anchor.z
        assert(x >= minX and x <= minX + 512, "marker stays within tile X bounds")
        assert(z >= minZ and z <= minZ + 512, "marker stays within tile Z bounds")
        local height = deckHeight + level * 800
            + math.min(x - minX, 511) * slope + math.min(z - minZ, 511)
        local bias = shape.data.rgba[index] == 0x1122338C and 30 or 31
        local nativeHeight = anchor.y
        if shape.alignType == ShapeEntityAlignType.MODEL then
            nativeHeight = ground(level, x, z)
        end
        near(p.y + nativeHeight, height + bias, "vertex follows marked surface without double alignment")
    end
end
local function centreShapes()
    local result = {}
    for _, shape in ipairs(submitted) do
        if not shape.destroyed and shape.coordGrid.x == minX and shape.coordGrid.z == minZ then
            result[#result + 1] = shape
        end
    end
    return result
end
local function verifyProbe(level, x, z)
    local expectedY = ground(level, math.min(x, minX + 511), math.min(z, minZ + 511)) + 31
    for _, p in ipairs(projected) do
        if p.x == x and p.z == z and math.abs(p.y - expectedY) < 0.001 then return end
    end
    error("split projection probe missed the marked deck at " .. x .. "," .. z)
end

for level = 0, 3 do
    for _, cornersOnly in ipairs({ false, true }) do
        Draw.Reset()
        submitted, projected = {}, {}
        slope = 1
        local settings = {
            coordGrid = coord(level, minX, minZ), outlineColour = 0x112233,
            fill = true, outlineCornersOnly = cornersOnly, drawDistance = 15360,
        }
        assert(Draw.Sync{ settings })
        local shape = centreShapes()[1]
        verifyDeck(shape, level)

        -- Terrain is retained until the caller resets on a region/bounds change.
        local data, oldSamples = shape.data, samples
        slope = 2
        assert(Draw.Sync{ settings })
        assert(shape.data == data and samples == oldSamples, "unchanged resident geometry is cached")
        Draw.Reset()
        submitted = {}
        assert(Draw.Sync{ settings })
        verifyDeck(centreShapes()[1], level)

        slope = 1
        Draw.Reset()
        submitted, projected = {}, {}
        local desired = {
            settings,
            { coordGrid = coord(level, minX + 512, minZ), outlineColour = 0xAABBCC },
            { coordGrid = coord(level, minX, minZ + 512), outlineColour = 0xAABBCC },
        }
        assert(Draw.Sync(desired))
        local centre = centreShapes()
        assert(#centre == 2, "bridge tile has main and split geometry on the first reconciliation")
        for _, retained in ipairs(centre) do verifyDeck(retained, level) end
        for _, offset in ipairs({ 192, 256, 320 }) do
            verifyProbe(level, minX + 512, minZ + offset)
            verifyProbe(level, minX + offset, minZ + 512)
        end
        verifyProbe(level, minX + 448, minZ + 256)
        verifyProbe(level, minX + 256, minZ + 448)
        oldSamples = samples
        Draw.UpdateCamera()
        assert(samples == oldSamples, "unchanged split camera geometry reuses terrain samples")
    end
end

Draw.Reset()
submitted = {}
World.GetGroundHeight = function(level) return 100 + level * 800, true end
local floors = {}
for level = 0, 3 do
    floors[#floors + 1] = { coordGrid = coord(level, minX, minZ) }
end
assert(Draw.Sync(floors))
for _, shape in ipairs(submitted) do
    for _, p in ipairs(shape.data.positions) do
        near(p.y + shape.anchor.y, 131 + shape.coordGrid.level * 800, "ordinary floor keeps its level")
    end
end

Draw.Reset()
submitted = {}
local available = false
World.GetGroundHeight = function()
    if not available then return -1, false end
    return 100, true
end
local pending = { { coordGrid = coord(0, minX, minZ) } }
assert(not Draw.Sync(pending), "unavailable terrain requests a logic retry")
assert(#submitted == 0, "unavailable terrain must not produce a marker")
available = true
assert(Draw.Sync(pending), "the same desired tile can load on a later reconciliation")
for _, p in ipairs(submitted[1].data.positions) do
    near(p.y + submitted[1].anchor.y, 131, "retry uses the newly available ground")
end

-- Failure at an edge, rather than the centre, must not become a cached height.
Draw.Reset()
submitted = {}
available = false
World.GetGroundHeight = function(_, x, z)
    if not available and x == minX + 511 and z == minZ + 511 then return -1, false end
    return 100 + (x - minX) + (z - minZ), true
end
assert(not Draw.Sync(pending), "unavailable corner prevents a partial main mesh")
assert(#submitted == 0, "failed corner does not upload partial geometry")
available = true
assert(Draw.Sync(pending), "failed corner samples are retried, not cached")
for _, p in ipairs(submitted[1].data.positions) do
    local x, z = p.x + submitted[1].anchor.x, p.z + submitted[1].anchor.z
    near(p.y + submitted[1].anchor.y,
        131 + math.min(x - minX, 511) + math.min(z - minZ, 511), "retried corner follows its terrain")
end
Draw.Reset()
print("test_draw_height: ok")
