local RegionBindings = {}

local ZONE_SIZE = 8
local cachedKey
local cachedBindings

local function coordAt(level, x, z)
    return CoordGrid.new(level, x // 64, z // 64, x % 64, z % 64)
end

function RegionBindings.toSource(coord)
    if not World.IsRegion() then return coord end

    local source = World.GetRegionSourceForCoordGrid(coord)
    if source == nil then return coord end
    return coordAt(
        source.level,
        source.x + (coord.x % ZONE_SIZE),
        source.z + (coord.z % ZONE_SIZE))
end

-- Returns current loaded coordinates paired with their canonical source
-- coordinates. The player's source zone is part of the cache key so a newly
-- loaded region with the same target bounds cannot reuse stale bindings.
function RegionBindings.resolveArea(from, range)
    if not World.IsRegion() then
        cachedKey = nil
        cachedBindings = nil
        return nil
    end

    local playerSource = World.GetRegionSourceForCoordGrid(from)
    local sourceKey = playerSource and playerSource:ToPacked() or -1
    local key = string.format("%d:%d:%d", from:ToPacked(), range, sourceKey)
    if key == cachedKey then return cachedBindings end

    local bindings = {}
    for x = from.x - range, from.x + range do
        for z = from.z - range, from.z + range do
            local target = coordAt(from.level, x, z)
            local source = World.GetRegionSourceForCoordGrid(target)
            if source ~= nil then
                bindings[#bindings + 1] = {
                    target = target,
                    source = coordAt(
                        source.level,
                        source.x + (x % ZONE_SIZE),
                        source.z + (z % ZONE_SIZE)),
                }
            end
        end
    end

    cachedKey = key
    cachedBindings = bindings
    return bindings
end

function RegionBindings.clear()
    cachedKey = nil
    cachedBindings = nil
end

return RegionBindings
