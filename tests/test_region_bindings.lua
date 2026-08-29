local function expect(actual, expected, message)
    if actual ~= expected then
        error(message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

local function newCoord(level, mapSquareX, mapSquareZ, localX, localZ)
    local coord = {
        level = level,
        x = mapSquareX * 64 + localX,
        z = mapSquareZ * 64 + localZ,
    }
    coord.mapSquareX = coord.x // 64
    coord.mapSquareZ = coord.z // 64
    coord.localX = coord.x % 64
    coord.localZ = coord.z % 64
    function coord:ToPacked()
        return (self.level << 28) | (self.x << 14) | self.z
    end
    return coord
end

CoordGrid = {
    new = function(level, mapSquareX, mapSquareZ, localX, localZ)
        return newCoord(level, mapSquareX, mapSquareZ, localX, localZ)
    end,
}

local inRegion = true
local sourceCalls = 0
World = {
    IsRegion = function() return inRegion end,
    GetRegionSourceForCoordGrid = function(coord)
        sourceCalls = sourceCalls + 1
        local targetZoneX = coord.x - (coord.x % 8)
        local targetZoneZ = coord.z - (coord.z % 8)
        return newCoord(
            1,
            (targetZoneX + 3200) // 64,
            (targetZoneZ + 6400) // 64,
            (targetZoneX + 3200) % 64,
            (targetZoneZ + 6400) % 64)
    end,
}

package.loaded["src/region_bindings"] = nil
local RegionBindings = require("src/region_bindings")
local target = newCoord(0, 50, 50, 13, 22)
local source = RegionBindings.toSource(target)
expect(source.level, 1, "source level")
expect(source.x, target.x + 3200, "source preserves tile x within zone")
expect(source.z, target.z + 6400, "source preserves tile z within zone")

sourceCalls = 0
local first = RegionBindings.resolveArea(target, 1)
expect(#first, 9, "three by three binding area")
expect(sourceCalls, 10, "area resolves player source and each tile once")
local second = RegionBindings.resolveArea(target, 1)
expect(second, first, "unchanged area reuses binding table")
expect(sourceCalls, 11, "cached lookup only verifies player source")

inRegion = false
expect(RegionBindings.toSource(target), target, "normal world coordinate is unchanged")
expect(RegionBindings.resolveArea(target, 1), nil, "normal world needs no binding map")

print("test_region_bindings: ok")
