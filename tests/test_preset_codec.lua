package.path = "./?.lua;" .. package.path

local Codec = require("src/preset_codec")
local Styles = require("src/styles")

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local function sortedCopy(tiles)
    local result = {}
    for _, tile in ipairs(tiles) do
        local style = Styles.normalize(tile)
        result[#result + 1] = {
            x = math.floor(tile.x),
            z = math.floor(tile.z),
            level = math.floor(tile.level or 0),
            outlineColour = style.outlineColour,
            fillColour = style.fillColour,
            fill = style.fill,
            outlineCornersOnly = style.outlineCornersOnly,
            outlineThickness = math.floor(style.outlineThickness * 10 + 0.5) / 10,
            label = tile.label ~= "" and tile.label or nil,
        }
    end
    table.sort(result, function(left, right)
        if left.level ~= right.level then return left.level < right.level end
        if left.x ~= right.x then return left.x < right.x end
        return left.z < right.z
    end)
    return result
end

local function roundTrip(name, tiles)
    local token, encodeError = Codec.encode(name, tiles)
    assert(token, encodeError)
    local decoded, decodeError = Codec.decode(token)
    assert(decoded, decodeError)
    equal(name, decoded.name, "preset name")

    local expected = sortedCopy(tiles)
    local actualTiles = sortedCopy(decoded.tiles)
    equal(#expected, #actualTiles, "tile count")
    for index, tile in ipairs(expected) do
        local actual = actualTiles[index]
        for _, field in ipairs({
            "x", "z", "level", "outlineColour", "fillColour",
            "fill", "outlineCornersOnly", "outlineThickness", "label",
        }) do
            equal(tile[field], actual[field], string.format("tile %d %s", index, field))
        end
    end
    return token
end

local cases = {
    {
        name = "Optimal cannon tiles",
        tiles = {
            { x = 3200, z = 3200, level = 0, colorIndex = 8, label = "A label" },
        },
    },
    {
        name = "Sparse and multi-floor",
        tiles = {
            {
                x = 12,
                z = -4,
                level = 3,
                outlineColour = 0x123456CC,
                fillColour = 0xABCDEF55,
                fill = true,
                outlineThickness = 7.5,
                outlineCornersOnly = true,
                label = "µ",
            },
            { x = 3210, z = 8170, level = 0, colorIndex = 4 },
            {
                x = 3210,
                z = 8199,
                level = 0,
                outlineColour = 0x10203040,
                fillColour = 0xFFEEDDCC,
                fill = false,
                outlineThickness = 0,
            },
            { x = 5000, z = 5000, level = 2, colorIndex = 8 },
        },
    },
    { name = "", tiles = {} },
}

local denseTiles = {}
for x = 3200, 3219 do
    for z = 3200, 3219 do
        denseTiles[#denseTiles + 1] = {
            x = x,
            z = z,
            level = 0,
            outlineColour = 0xFF6600FF,
            fillColour = 0x2244AA66,
            fill = (x + z) % 3 ~= 0,
            outlineThickness = ((x + z) % 20) / 2,
        }
    end
end
cases[#cases + 1] = { name = "Twenty by twenty", tiles = denseTiles }

local repeatedLabels = {}
for index = 1, 100 do
    repeatedLabels[index] = {
        x = 3300 + index // 10,
        z = 3300 + index % 10,
        level = 0,
        outlineColour = 0x55CCFFFF,
        fillColour = 0x1020308C,
        fill = true,
        outlineThickness = 2.5,
        label = index % 3 == 0 and "Player active" or "Cannon",
    }
end
cases[#cases + 1] = { name = "Repeated labels", tiles = repeatedLabels }

for _, case in ipairs(cases) do
    local token = roundTrip(case.name, case.tiles)
    print(string.format("%-24s %5d tiles %5d characters", case.name, #case.tiles, #token))
end

math.randomseed(0x544D32)
for caseIndex = 1, 200 do
    local tiles = {}
    local x = math.random(-100, 16000)
    local z = math.random(-100, 16000)
    for index = 1, math.random(1, 250) do
        if math.random(4) == 1 then
            x = x + math.random(1, 4)
            z = z + math.random(-40, 40)
        else
            z = z + math.random(1, 140)
        end
        local tile = {
            x = x,
            z = z,
            level = math.random(0, 3),
            outlineColour = (math.random(0, 0xFFFFFF) << 8)
                | math.random(0, 0xFF),
            fillColour = (math.random(0, 0xFFFFFF) << 8)
                | math.random(0, 0xFF),
            fill = math.random(0, 1) == 1,
            outlineThickness = math.random(0, 20) / 2,
        }
        if math.random(10) == 1 then
            tile.label = "Tile " .. caseIndex .. ":" .. index
        end
        tiles[#tiles + 1] = tile
    end
    roundTrip("Random " .. caseIndex, tiles)
end

local invalid, invalidError = Codec.decode("TM2!")
assert(invalid == nil and invalidError ~= nil)

local reported, reportedError = Codec.decode(
    "TM2IQd5YW5pbGxlA92Z4AbNAQgBhc8-_2qmMowAFAAAAA")
assert(reported ~= nil, reportedError)
equal("yanille", reported.name, "reported export name decodes")
equal(3, #reported.tiles, "reported export tiles decode")

print("preset_codec tests passed")
