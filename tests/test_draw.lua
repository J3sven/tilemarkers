local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function vector(x, y, z)
    return { x = x, y = y, z = z }
end

Vector3 = { new = vector }
ShapeData = {
    new = function()
        return { positions = {}, rgba = {}, lines = {}, tris = {} }
    end,
}

local submitted = {}
local function managedShape()
    return {
        SetShapeData = function(self, shapeData)
            self.shapeData = shapeData
            return true
        end,
        Destroy = function(self)
            self.destroyed = true
            return true
        end,
    }
end

ShapeList = {
    CreateInstance = function(name)
        local shape = managedShape()
        shape.name = name
        submitted[#submitted + 1] = shape
        return shape
    end,
}
World = {
    GetGroundHeight = function(_, x, z)
        return (x // 512) * 10 + (z // 512), true
    end,
}
ScreenConvert = {
    Vector3ToScreen = function(position)
        return { x = position.x / 16, y = position.z / 16 }
    end,
}

local function coord(x, z)
    return {
        level = 2,
        ToCoordFine = function()
            return { position = vector(x, 0, z) }
        end,
    }
end

package.loaded["src/draw"] = nil
local Draw = require("src/draw")
expect(type(Draw.Tile), "function", "draw module exports tile renderer")
expect(type(Draw.BeginFrame), "function", "draw module exports frame lifecycle")
expect(type(Draw.Reset), "function", "draw module exports cleanup")

local westCoord = coord(5120, 7168)
local drawn = Draw.Tile{
    coordGrid = westCoord,
    outlineColour = 0x112233,
    fill = true,
    outlineThickness = 3.5,
    ignoreDepth = true,
}
expect(drawn, true, "tile draws")
expect(#submitted, 1, "tile creates one managed shape")
expect(submitted[1].shapeData.rgba[1], 0x112233FF, "outline defaults opaque")
expect(submitted[1].shapeData.rgba[5], 0x1122338C, "fill defaults to 55 percent")
expect(#submitted[1].shapeData.lines, 8, "outline has four exterior lines")
expect(#submitted[1].shapeData.tris, 6, "fill has two triangles")
expect(submitted[1].shapeData.positions[1].x, -256, "mesh starts at local tile edge")
expect(submitted[1].lineWidth, 3.5, "outline thickness reaches shape")
expect(submitted[1].ignoreDepth, true, "depth setting reaches shape")

Draw.Tile{
    coordGrid = westCoord,
    outlineColour = 0x11223320,
    fill = true,
}
expect(#submitted, 1, "redrawing a tile reuses its shape")
expect(submitted[1].shapeData.rgba[1], 0x11223320, "embedded outline alpha is retained")

Draw.Tile{
    coordGrid = westCoord,
    outlineColour = 0x010203,
    outlineCornersOnly = true,
}
expect(#submitted[1].shapeData.lines, 16, "corner-only outline has two lines per side")
expect(submitted[1].shapeData.positions[1].x, -256, "corner starts at tile edge")
expect(submitted[1].shapeData.positions[2].x, -128, "corner ends at quarter edge")

local eastCoord = coord(5632, 7168)
Draw.Reset()
submitted = {}
Draw.BeginFrame()
Draw.Tile{
    coordGrid = westCoord,
    outlineColour = 0x556677,
    outlineThickness = 4.0,
}
Draw.Tile{
    coordGrid = eastCoord,
    outlineColour = 0xAABBCC,
    outlineThickness = 4.0,
}
Draw.BeginFrame()
Draw.Tile{
    coordGrid = westCoord,
    outlineColour = 0x556677,
    outlineThickness = 4.0,
}
Draw.Tile{
    coordGrid = eastCoord,
    outlineColour = 0xAABBCC,
    outlineThickness = 4.0,
}
expect(#submitted, 4, "differently coloured neighbours create split outlines")
local westMain = submitted[1]
local eastMain = submitted[2]
local eastSplit = submitted[3]
local westSplit = submitted[4]
expect(#westMain.shapeData.lines, 6, "west tile omits split east edge")
expect(#eastMain.shapeData.lines, 6, "east tile omits split west edge")
expect(westSplit.lineWidth, 2.0, "west shared edge uses half thickness")
expect(eastSplit.lineWidth, 2.0, "east shared edge uses half thickness")
expect(westSplit.shapeData.positions[1].x, 240, "west colour is inset westward")
expect(eastSplit.shapeData.positions[1].x, -240, "east colour is inset eastward")

Draw.BeginFrame()
expect(westMain.destroyed, nil, "active shape survives one untouched frame")
Draw.BeginFrame()
expect(westMain.destroyed, true, "stale shape is destroyed")

Draw.Reset()
for _, shape in ipairs(submitted) do
    expect(shape.destroyed, true, "reset destroys every managed shape")
end

print("test_draw: ok")
