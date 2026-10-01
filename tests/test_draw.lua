local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function vector(x, y, z)
    return { x = x, y = y, z = z }
end

local stats = { builds = 0, uploads = 0, properties = 0, samples = 0, projections = 0 }
Vector3 = { new = vector }
ShapeEntityAlignType = { NONE = 0 }
ShapeData = { new = function()
    stats.builds = stats.builds + 1
    return {}
end }
local submitted, failUploads = {}, 0
ShapeList = { CreateEntity = function(name)
    local values = { name = name, uploads = 0, coordWrites = 0 }
    local shape = setmetatable({}, {
        __index = values,
        __newindex = function(_, key, value)
            assert(key ~= "translation", "fixed entities have no translation transform")
            stats.properties = stats.properties + 1
            if key == "coordGrid" then
                values.coordWrites = values.coordWrites + 1
                expect(values.coordWrites, 1, "resident entities never move")
            end
            values[key] = value
        end,
    })
    values.SetShapeData = function(_, data)
        assert(#data.positions > 0 and (#data.lines > 0 or #data.tris > 0),
            "empty geometry is invalid for a native entity")
        expect(#data.rgba, #data.positions, "all vertices have colours")
        for _, indices in ipairs({ data.lines, data.tris }) do
            for _, index in ipairs(indices) do
                assert(index >= 0 and index < #data.positions, "valid zero-based vertex index")
            end
        end
        stats.uploads = stats.uploads + 1
        values.uploads = values.uploads + 1
        if failUploads > 0 then
            failUploads = failUploads - 1
            return false
        end
        values.shapeData = data
        return true
    end
    values.SetDrawDistance = function(_, distance)
        stats.properties = stats.properties + 1
        values.drawDistance = distance
    end
    values.Destroy = function()
        assert(not values.destroyed, "entity is destroyed only once")
        values.destroyed = true
        return true
    end
    submitted[#submitted + 1] = shape
    return shape
end }
World = { GetGroundHeight = function(_, x, z)
    stats.samples = stats.samples + 1
    return (x // 512) * 10 + (z // 512), true
end }
local zoom = 1
ScreenConvert = { Vector3ToScreen = function(position)
    stats.projections = stats.projections + 1
    return { x = position.x * zoom / 16, y = position.z * zoom / 16 }
end }

local function coord(x, z, level)
    return {
        level = level or 2, x = x, z = z,
        ToCoordFine = function()
            return { position = vector(x * 512 + 256, 0, z * 512 + 256) }
        end,
    }
end
local function marker(at, colour)
    return { coordGrid = at, outlineColour = colour, outlineThickness = 4, drawDistance = 15360 }
end
local function shapesAt(at)
    local result = {}
    for _, shape in ipairs(submitted) do
        local placed = shape.coordGrid
        if not shape.destroyed and placed.level == at.level and placed.x == at.x and placed.z == at.z then
            result[#result + 1] = shape
        end
    end
    return result
end
local function shapeWithLines(at, count)
    for _, shape in ipairs(shapesAt(at)) do
        if #shape.shapeData.lines == count then return shape end
    end
    error("missing shape with " .. count .. " line indices")
end
local function snapshot()
    local result = {}
    for key, value in pairs(stats) do result[key] = value end
    return result
end
local function expectRetained(before, message)
    for _, key in ipairs({ "builds", "uploads", "properties", "samples" }) do
        expect(stats[key], before[key], message .. " (" .. key .. ")")
    end
end

package.loaded["src/draw"] = nil
local Draw = require("src/draw")
local westCoord, eastCoord = coord(10, 14), coord(11, 14)
local west = marker(westCoord, 0x112233)
west.fill = true
assert(Draw.Sync{ west })
local westMain = shapeWithLines(westCoord, 8)
expect(westMain.shapeData.rgba[1], 0x112233FF, "outline defaults opaque")
expect(westMain.shapeData.rgba[5], 0x1122338C, "fill defaults to 55 percent")
expect(#westMain.shapeData.tris, 6, "fill has two triangles")
expect(westMain.shapeData.positions[1].x, -256, "mesh starts at local tile edge")

local before = snapshot()
for _ = 1, 60 do Draw.UpdateCamera() end
expectRetained(before, "ordinary markers do no per-frame mesh work")
expect(stats.projections, before.projections, "ordinary markers need no camera projections")
-- Different input objects with equivalent normalized styles are still unchanged.
assert(Draw.Sync{ {
    coordGrid = coord(10, 14), outlineColour = 0x112233FF, fill = true,
    outlineThickness = "4", drawDistance = 15360,
} })
expectRetained(before, "equivalent desired set preserves native state")

west.outlineColour = 0x11223320
assert(Draw.Sync{ west })
expect(shapesAt(westCoord)[1], westMain, "colour changes retain the fixed entity")
expect(westMain.shapeData.rgba[1], 0x11223320, "embedded outline alpha is retained")
west.fill = false
west.outlineCornersOnly = true
assert(Draw.Sync{ west })
expect(#westMain.shapeData.lines, 16, "corner-only outline has two lines per side")
expect(westMain.shapeData.positions[2].x, -128, "corner ends at quarter edge")
before = snapshot()
west.ignoreDepth = true
west.drawDistance = 20000
west.outlineThickness = 5
assert(Draw.Sync{ west })
expect(stats.builds, before.builds, "non-geometric styles do not rebuild main geometry")
expect(stats.uploads, before.uploads, "non-geometric styles do not upload main geometry")
expect(stats.properties, before.properties + 3, "only changed depth, width and culling properties update")
expect(westMain.coordWrites, 1, "style edits never reposition an entity")
before = snapshot()
assert(Draw.Sync{ west })
expectRetained(before, "repeating property edits is a no-op")

Draw.Reset()
submitted = {}
west = marker(westCoord, 0x556677)
local east = marker(eastCoord, 0xAABBCC)
local plainCoord = coord(30, 30)
local plain = marker(plainCoord, 0xABCDEF)
assert(Draw.Sync{ west, east, plain })
westMain = shapeWithLines(westCoord, 6)
local eastMain = shapeWithLines(eastCoord, 6)
local westSplit = shapeWithLines(westCoord, 2)
local eastSplit = shapeWithLines(eastCoord, 2)
local plainShape = shapeWithLines(plainCoord, 8)
expect(westSplit.shapeData.positions[1].x, 240, "west colour is inset on the first reconciliation")
expect(eastSplit.shapeData.positions[1].x, -240, "east colour is inset on the first reconciliation")
expect(westSplit.lineWidth, 2, "shared edges use half the normal line width")
before = snapshot()
assert(Draw.Sync{ plain, east, west })
expectRetained(before, "input order does not affect topology")
for _ = 1, 60 do Draw.UpdateCamera() end
expectRetained(before, "unchanged camera preserves split geometry")

local mainUploads, plainUploads = westMain.uploads, plainShape.uploads
zoom = 2
Draw.UpdateCamera()
expect(westSplit.shapeData.positions[1].x, 248, "camera zoom updates screen-space split inset")
expect(eastSplit.shapeData.positions[1].x, -248, "both halves respond to camera zoom")
expect(westMain.uploads, mainUploads, "camera never uploads main geometry")
expect(plainShape.uploads, plainUploads, "camera never touches plain markers")
before = snapshot()
zoom = 2.01
Draw.UpdateCamera()
expectRetained(before, "camera movement below fine-unit precision does not rebuild geometry")

assert(Draw.Sync{ west, plain })
expect(eastMain.destroyed, true, "omitted main entity is deleted immediately")
expect(eastSplit.destroyed, true, "omitted split entity is deleted immediately")
expect(westSplit.destroyed, true, "surviving tile removes obsolete split geometry immediately")
expect(#westMain.shapeData.lines, 8, "surviving tile restores its full outline without a frame delay")
east.outlineColour = west.outlineColour
assert(Draw.Sync{ west, east, plain })
expect(#shapesAt(westCoord), 1, "matching colours do not split the shared edge")
expect(#shapesAt(eastCoord), 1, "matching neighbour has only main geometry")

Draw.Reset()
submitted = {}
zoom = 1
local centreCoord = coord(50, 50)
local centre = marker(centreCoord, 0x111111)
local north = marker(coord(50, 51), 0x222222)
local south = marker(coord(50, 49), 0x333333)
local left = marker(coord(49, 50), 0x444444)
local right = marker(coord(51, 50), 0x555555)
assert(Draw.Sync{ centre, north, south, left, right })
expect(#shapesAt(centreCoord), 1, "four split edges need no invalid empty main shape")
local centreSplit = shapeWithLines(centreCoord, 8)
expect(centreSplit.shapeData.positions[1].z, -240, "surrounded tile keeps its south split edge")
expect(centreSplit.shapeData.positions[3].z, 240, "surrounded tile keeps its north split edge")
expect(centreSplit.shapeData.positions[5].x, -240, "surrounded tile keeps its west split edge")
expect(centreSplit.shapeData.positions[7].x, 240, "surrounded tile keeps its east split edge")
centre.fill = true
assert(Draw.Sync{ centre, north, south, left, right })
local centreFill = shapeWithLines(centreCoord, 0)
expect(#centreFill.shapeData.tris, 6, "surrounded filled tile has valid triangle-only main geometry")
expect(shapeWithLines(centreCoord, 8), centreSplit, "adding fill retains split entity")
centre.fill = false
assert(Draw.Sync{ centre, north, south, left, right })
expect(centreFill.destroyed, true, "removing fill deletes now-empty main entity")
assert(Draw.Sync{ centre, south, left, right })
expect(#shapeWithLines(centreCoord, 2).shapeData.tris, 0, "removing a neighbour restores its main edge")
expect(shapeWithLines(centreCoord, 6), centreSplit, "remaining split sides retain their entity")
centre.outlineCornersOnly = true
assert(Draw.Sync{ centre, north, south, left, right })
expect(#shapesAt(centreCoord), 1, "surrounded corner-only tile also omits empty main geometry")
expect(#centreSplit.shapeData.lines, 16, "surrounded corner-only tile retains all split corners")

Draw.Reset()
submitted = {}
failUploads = 1
assert(not Draw.Sync{ west }, "native upload failure asks for another reconciliation")
expect(submitted[1].destroyed, true, "failed native entity is released")
assert(Draw.Sync{ west }, "retry configures the requested tile")
local recovered = shapeWithLines(westCoord, 8)
failUploads = 1
west.outlineColour = 0x987654
assert(not Draw.Sync{ west })
expect(recovered.destroyed, true, "failed replacement does not leave an invalid retained entity")
west.outlineColour = 0x556677
assert(Draw.Sync{ west }, "reverting after a failed upload still recreates missing geometry")
expect(shapeWithLines(westCoord, 8).shapeData.rgba[1], 0x556677FF, "recovered marker has the requested style")
assert(Draw.Sync{})
for _, shape in ipairs(submitted) do
    expect(shape.destroyed, true, "empty desired set deletes every resident")
end
Draw.Reset()
print("test_draw: ok")
