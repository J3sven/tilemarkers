local Codec = {}
local Styles = require("src/styles")

local TOKEN_PREFIX = "TM2"
local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local BASE64_VALUES = {}
local MAX_TILES = 100000
local MAX_NAME_BYTES = 128
local MAX_LABEL_BYTES = 128
local DICTIONARY_FLAG = 0x10
local MORTON_COORDINATES_FLAG = 0x20
local PREFIX_DICTIONARY_FLAG = 0x40

for index = 1, #BASE64_ALPHABET do
    BASE64_VALUES[BASE64_ALPHABET:sub(index, index)] = index - 1
end

local function base64Encode(source)
    local result = {}
    local index = 1
    while index <= #source do
        local first = source:byte(index)
        local second = source:byte(index + 1)
        local third = source:byte(index + 2)
        local combined = first << 16
        if second ~= nil then
            combined = combined | (second << 8)
        end
        if third ~= nil then
            combined = combined | third
        end

        result[#result + 1] = BASE64_ALPHABET:sub(((combined >> 18) & 0x3F) + 1, ((combined >> 18) & 0x3F) + 1)
        result[#result + 1] = BASE64_ALPHABET:sub(((combined >> 12) & 0x3F) + 1, ((combined >> 12) & 0x3F) + 1)
        if second ~= nil then
            result[#result + 1] = BASE64_ALPHABET:sub(((combined >> 6) & 0x3F) + 1, ((combined >> 6) & 0x3F) + 1)
        end
        if third ~= nil then
            result[#result + 1] = BASE64_ALPHABET:sub((combined & 0x3F) + 1, (combined & 0x3F) + 1)
        end
        index = index + 3
    end
    return table.concat(result)
end

local function base64Decode(source)
    if source == "" or #source % 4 == 1 then
        return nil, "Invalid preset token."
    end
    local result = {}
    local index = 1
    while index <= #source do
        local available = math.min(4, #source - index + 1)
        local combined = 0
        for offset = 0, available - 1 do
            local value = BASE64_VALUES[source:sub(index + offset, index + offset)]
            if value == nil then
                return nil, "Preset token contains unsupported characters."
            end
            combined = combined | (value << (18 - offset * 6))
        end
        result[#result + 1] = string.char((combined >> 16) & 0xFF)
        if available >= 3 then
            result[#result + 1] = string.char((combined >> 8) & 0xFF)
        end
        if available == 4 then
            result[#result + 1] = string.char(combined & 0xFF)
        end
        index = index + 4
    end
    return table.concat(result)
end

local function writeVaruint(parts, value)
    repeat
        local byte = value % 128
        value = value // 128
        if value > 0 then
            byte = byte | 0x80
        end
        parts[#parts + 1] = string.char(byte)
    until value == 0
end

local function varuintLength(value)
    local length = 1
    while value >= 128 do
        value = value // 128
        length = length + 1
    end
    return length
end

local function zigzagEncode(value)
    return value >= 0 and value * 2 or -value * 2 - 1
end

local function zigzagDecode(value)
    return value % 2 == 0 and value // 2 or -((value + 1) // 2)
end

local function normaliseName(name)
    local words = {}
    for word in name:gmatch("[A-Za-z0-9]+") do
        words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2):lower()
    end
    local normalised = table.concat(words)
    if normalised == "" then
        return "Preset"
    end
    return normalised:sub(1, 64)
end

Codec.normaliseName = normaliseName

local function newReader(source)
    return { source = source, position = 1 }
end

local function readBytes(reader, length)
    if length < 0 or reader.position + length - 1 > #reader.source then
        return nil
    end
    local value = reader.source:sub(reader.position, reader.position + length - 1)
    reader.position = reader.position + length
    return value
end

local function readByte(reader)
    local value = reader.source:byte(reader.position)
    if value ~= nil then
        reader.position = reader.position + 1
    end
    return value
end

local function readVaruint(reader)
    local value = 0
    local shift = 0
    for _ = 1, 9 do
        local byte = readByte(reader)
        if byte == nil then
            return nil
        end
        value = value | ((byte & 0x7F) << shift)
        if (byte & 0x80) == 0 then
            return value
        end
        shift = shift + 7
    end
    return nil
end

local function writeUInt32(parts, value)
    value = math.floor(value) & 0xFFFFFFFF
    parts[#parts + 1] = string.char(
        (value >> 24) & 0xFF,
        (value >> 16) & 0xFF,
        (value >> 8) & 0xFF,
        value & 0xFF)
end

local function readUInt32(reader)
    local first = readByte(reader)
    local second = readByte(reader)
    local third = readByte(reader)
    local fourth = readByte(reader)
    if fourth == nil then return nil end
    return (first << 24) | (second << 16) | (third << 8) | fourth
end

local function integer(value)
    value = tonumber(value)
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return math.floor(value)
end

local function mortonEncode(x, z)
    local value = 0
    for bit = 0, 13 do
        value = value
            | (((z >> bit) & 1) << (bit * 2))
            | (((x >> bit) & 1) << (bit * 2 + 1))
    end
    return value
end

local function mortonDecode(value)
    local x = 0
    local z = 0
    for bit = 0, 13 do
        z = z | (((value >> (bit * 2)) & 1) << bit)
        x = x | (((value >> (bit * 2 + 1)) & 1) << bit)
    end
    return x, z
end

local function prepareTiles(tiles)
    if #tiles > MAX_TILES then
        return nil, "Preset contains too many tiles."
    end

    local ordered = {}
    for _, tile in ipairs(tiles) do
        if type(tile) ~= "table" then
            return nil, "Invalid tile data."
        end
        local x = integer(tile.x)
        local z = integer(tile.z)
        local level = integer(tile.level) or 0
        local label = type(tile.label) == "string" and tile.label or ""
        local style = Styles.normalize(tile)
        if x == nil or z == nil or level < 0 or level > 3
            or #label > MAX_LABEL_BYTES then
            return nil, "Invalid tile data."
        end
        ordered[#ordered + 1] = {
            x = x,
            z = z,
            level = level,
            outlineColour = style.outlineColour,
            fillColour = style.fillColour,
            fill = style.fill,
            outlineCornersOnly = style.outlineCornersOnly,
            outlineThickness = style.outlineThickness,
            label = label,
        }
    end
    return ordered
end

local function sortTiles(tiles, useMortonCoordinates)
    table.sort(tiles, function(left, right)
        if left.level ~= right.level then
            return left.level < right.level
        elseif useMortonCoordinates then
            local leftMorton = mortonEncode(left.x, left.z)
            local rightMorton = mortonEncode(right.x, right.z)
            if leftMorton ~= rightMorton then
                return leftMorton < rightMorton
            end
        elseif left.x ~= right.x then
            return left.x < right.x
        end
        return left.z < right.z
    end)
end

local function writeCoordinateDelta(parts, deltaX, deltaZ)
    if deltaX == 0 and deltaZ >= 1 and deltaZ <= 128 then
        parts[#parts + 1] = string.char(deltaZ - 1)
    elseif deltaX == 1 and deltaZ >= -32 and deltaZ <= 31 then
        parts[#parts + 1] = string.char(0x80 + deltaZ + 32)
    else
        parts[#parts + 1] = string.char(0xC0)
        writeVaruint(parts, deltaX)
        writeVaruint(parts, zigzagEncode(deltaZ))
    end
end

local function encodeCoordinates(tiles, levelCounts, useMortonCoordinates)
    local parts = {}
    local tileIndex = 1
    for level = 0, 3 do
        local count = levelCounts[level + 1]
        if count > 0 then
            writeVaruint(parts, count)
            local first = tiles[tileIndex]
            if useMortonCoordinates then
                local previousMorton = mortonEncode(first.x, first.z)
                writeVaruint(parts, previousMorton)
                tileIndex = tileIndex + 1
                for _ = 2, count do
                    local tile = tiles[tileIndex]
                    local morton = mortonEncode(tile.x, tile.z)
                    writeVaruint(parts, morton - previousMorton)
                    previousMorton = morton
                    tileIndex = tileIndex + 1
                end
            else
                writeVaruint(parts, zigzagEncode(first.x))
                writeVaruint(parts, zigzagEncode(first.z))
                local previousX = first.x
                local previousZ = first.z
                tileIndex = tileIndex + 1
                for _ = 2, count do
                    local tile = tiles[tileIndex]
                    writeCoordinateDelta(parts, tile.x - previousX, tile.z - previousZ)
                    previousX = tile.x
                    previousZ = tile.z
                    tileIndex = tileIndex + 1
                end
            end
        end
    end
    return table.concat(parts)
end

local function commonPrefixLength(left, right)
    local limit = math.min(#left, #right)
    local length = 0
    while length < limit
        and left:byte(length + 1) == right:byte(length + 1) do
        length = length + 1
    end
    return length
end

function Codec.encode(name, tiles)
    if type(name) ~= "string" or type(tiles) ~= "table" or #name > MAX_NAME_BYTES then
        return nil, "Invalid preset data."
    end
    local ordered, prepareError = prepareTiles(tiles)
    if ordered == nil then
        return nil, prepareError
    end

    local canUseMortonCoordinates = true
    for _, tile in ipairs(ordered) do
        if tile.x < 0 or tile.x > 0x3FFF or tile.z < 0 or tile.z > 0x3FFF then
            canUseMortonCoordinates = false
            break
        end
    end

    local levelCounts = { 0, 0, 0, 0 }
    local levelMask = 0
    for _, tile in ipairs(ordered) do
        levelCounts[tile.level + 1] = levelCounts[tile.level + 1] + 1
        levelMask = levelMask | (1 << tile.level)
    end

    sortTiles(ordered, false)
    local coordinates = encodeCoordinates(ordered, levelCounts, false)
    local useMortonCoordinates = false
    if canUseMortonCoordinates and #ordered > 0 then
        local mortonOrdered = {}
        for index, tile in ipairs(ordered) do
            mortonOrdered[index] = tile
        end
        sortTiles(mortonOrdered, true)
        local mortonCoordinates = encodeCoordinates(mortonOrdered, levelCounts, true)
        if #mortonCoordinates < #coordinates then
            ordered = mortonOrdered
            coordinates = mortonCoordinates
            useMortonCoordinates = true
        end
    end

    local labels = {}
    local insertionIndexes = {}
    local insertionDictionary = {}
    local rawLabelBytes = 0
    for _, tile in ipairs(ordered) do
        if tile.label ~= "" then
            labels[#labels + 1] = tile.label
            rawLabelBytes = rawLabelBytes + varuintLength(#tile.label) + #tile.label
            local labelIndex = insertionIndexes[tile.label]
            if labelIndex == nil then
                labelIndex = #insertionDictionary
                insertionIndexes[tile.label] = labelIndex
                insertionDictionary[#insertionDictionary + 1] = tile.label
            end
        end
    end

    local dictionaryBytes = varuintLength(#insertionDictionary)
    for _, label in ipairs(insertionDictionary) do
        dictionaryBytes = dictionaryBytes + varuintLength(#label) + #label
    end
    for _, label in ipairs(labels) do
        dictionaryBytes = dictionaryBytes + varuintLength(insertionIndexes[label])
    end

    local prefixDictionary = {}
    for index, label in ipairs(insertionDictionary) do
        prefixDictionary[index] = label
    end
    table.sort(prefixDictionary)
    local prefixIndexes = {}
    local prefixDictionaryBytes = varuintLength(#prefixDictionary)
    local previousLabel = ""
    for index, label in ipairs(prefixDictionary) do
        prefixIndexes[label] = index - 1
        local prefixLength = commonPrefixLength(previousLabel, label)
        local suffixLength = #label - prefixLength
        prefixDictionaryBytes = prefixDictionaryBytes
            + varuintLength(prefixLength)
            + varuintLength(suffixLength)
            + suffixLength
        previousLabel = label
    end
    for _, label in ipairs(labels) do
        prefixDictionaryBytes = prefixDictionaryBytes + varuintLength(prefixIndexes[label])
    end

    local useDictionary = #labels > 0
        and math.min(dictionaryBytes, prefixDictionaryBytes) < rawLabelBytes
    local usePrefixDictionary = useDictionary and prefixDictionaryBytes < dictionaryBytes
    local dictionary = usePrefixDictionary and prefixDictionary or insertionDictionary
    local labelIndexes = usePrefixDictionary and prefixIndexes or insertionIndexes

    local styles = {}
    local styleIndexes = {}
    for _, tile in ipairs(ordered) do
        local thickness = math.floor(tile.outlineThickness * 10 + 0.5)
        local styleFlags = (tile.fill == nil and 0x04 or tile.fill and 1 or 0)
            | (tile.outlineCornersOnly == nil and 0x08 or tile.outlineCornersOnly and 2 or 0)
        local styleKey = string.format(
            "%08X:%08X:%d:%d",
            tile.outlineColour,
            tile.fillColour,
            styleFlags,
            thickness)
        local styleIndex = styleIndexes[styleKey]
        if styleIndex == nil then
            styleIndex = #styles
            styleIndexes[styleKey] = styleIndex
            styles[#styles + 1] = {
                outlineColour = tile.outlineColour,
                fillColour = tile.fillColour,
                flags = styleFlags,
                thickness = thickness,
            }
        end
        tile.styleIndex = styleIndex
    end

    local flags = levelMask
        | (useDictionary and DICTIONARY_FLAG or 0)
        | (useMortonCoordinates and MORTON_COORDINATES_FLAG or 0)
        | (usePrefixDictionary and PREFIX_DICTIONARY_FLAG or 0)
    local parts = { string.char(flags) }
    writeVaruint(parts, #name)
    parts[#parts + 1] = name
    parts[#parts + 1] = coordinates

    writeVaruint(parts, #styles)
    for _, style in ipairs(styles) do
        writeUInt32(parts, style.outlineColour)
        writeUInt32(parts, style.fillColour)
        parts[#parts + 1] = string.char(style.flags, style.thickness)
    end
    for _, tile in ipairs(ordered) do
        writeVaruint(parts, (tile.styleIndex << 1) | (tile.label ~= "" and 1 or 0))
    end

    if useDictionary then
        writeVaruint(parts, #dictionary)
        local previousDictionaryLabel = ""
        for _, label in ipairs(dictionary) do
            if usePrefixDictionary then
                local prefixLength = commonPrefixLength(previousDictionaryLabel, label)
                local suffix = label:sub(prefixLength + 1)
                writeVaruint(parts, prefixLength)
                writeVaruint(parts, #suffix)
                parts[#parts + 1] = suffix
                previousDictionaryLabel = label
            else
                writeVaruint(parts, #label)
                parts[#parts + 1] = label
            end
        end
        for _, label in ipairs(labels) do
            writeVaruint(parts, labelIndexes[label])
        end
    else
        for _, label in ipairs(labels) do
            writeVaruint(parts, #label)
            parts[#parts + 1] = label
        end
    end

    return TOKEN_PREFIX .. base64Encode(table.concat(parts))
end

local function readCoordinates(reader, level, count, tiles)
    local encodedX = readVaruint(reader)
    local encodedZ = readVaruint(reader)
    if encodedX == nil or encodedZ == nil then
        return false
    end
    local x = zigzagDecode(encodedX)
    local z = zigzagDecode(encodedZ)
    tiles[#tiles + 1] = { x = x, z = z, level = level }

    for _ = 2, count do
        local code = readByte(reader)
        if code == nil then
            return false
        end
        local deltaX
        local deltaZ
        if code < 0x80 then
            deltaX = 0
            deltaZ = code + 1
        elseif code < 0xC0 then
            deltaX = 1
            deltaZ = code - 0xA0
        elseif code == 0xC0 then
            deltaX = readVaruint(reader)
            local encodedDeltaZ = readVaruint(reader)
            if deltaX == nil or encodedDeltaZ == nil then
                return false
            end
            deltaZ = zigzagDecode(encodedDeltaZ)
        else
            return false
        end
        x = x + deltaX
        z = z + deltaZ
        tiles[#tiles + 1] = { x = x, z = z, level = level }
    end
    return true
end

local function readMortonCoordinates(reader, level, count, tiles)
    local morton = readVaruint(reader)
    if morton == nil or morton > 0x0FFFFFFF then
        return false
    end
    local x, z = mortonDecode(morton)
    tiles[#tiles + 1] = { x = x, z = z, level = level }
    for _ = 2, count do
        local delta = readVaruint(reader)
        if delta == nil or morton + delta > 0x0FFFFFFF then
            return false
        end
        morton = morton + delta
        x, z = mortonDecode(morton)
        tiles[#tiles + 1] = { x = x, z = z, level = level }
    end
    return true
end

function Codec.decode(token)
    if type(token) ~= "string" or token:sub(1, #TOKEN_PREFIX) ~= TOKEN_PREFIX then
        return nil, "Expected a TM2 preset token."
    end
    local binary, decodeError = base64Decode(token:sub(#TOKEN_PREFIX + 1))
    if binary == nil then
        return nil, decodeError
    end

    local reader = newReader(binary)
    local flags = readByte(reader)
    if flags == nil or (flags & 0x80) ~= 0
        or (flags & PREFIX_DICTIONARY_FLAG) ~= 0
            and (flags & DICTIONARY_FLAG) == 0 then
        return nil, "Invalid preset token header."
    end
    local levelMask = flags & 0x0F
    local usesDictionary = (flags & DICTIONARY_FLAG) ~= 0
    local usesMortonCoordinates = (flags & MORTON_COORDINATES_FLAG) ~= 0
    local usesPrefixDictionary = (flags & PREFIX_DICTIONARY_FLAG) ~= 0
    local nameLength = readVaruint(reader)
    if nameLength == nil or nameLength > MAX_NAME_BYTES then
        return nil, "Invalid preset name length."
    end
    local name = readBytes(reader, nameLength)
    if name == nil then
        return nil, "Invalid preset token contents."
    end

    local tiles = {}
    for level = 0, 3 do
        if (levelMask & (1 << level)) ~= 0 then
            local count = readVaruint(reader)
            if count == nil or count < 1 or #tiles + count > MAX_TILES
                or not (usesMortonCoordinates
                    and readMortonCoordinates(reader, level, count, tiles)
                    or not usesMortonCoordinates
                        and readCoordinates(reader, level, count, tiles)) then
                return nil, "Invalid tile data in preset token."
            end
        end
    end

    local styleCount = readVaruint(reader)
    if styleCount == nil or styleCount > #tiles
        or (#tiles > 0 and styleCount < 1) then
        return nil, "Invalid style dictionary in preset token."
    end
    local styles = {}
    for index = 1, styleCount do
        local outlineColour = readUInt32(reader)
        local fillColour = readUInt32(reader)
        local styleFlags = readByte(reader)
        local thickness = readByte(reader)
        if outlineColour == nil or fillColour == nil or styleFlags == nil
            or (styleFlags & 0xF0) ~= 0
            or (styleFlags & 0x05) == 0x05 or (styleFlags & 0x0A) == 0x0A
            or thickness == nil or thickness > 100
        then
            return nil, "Invalid tile style in preset token."
        end
        local fill
        if (styleFlags & 0x04) == 0 then
            fill = (styleFlags & 1) ~= 0
        end
        local outlineCornersOnly
        if (styleFlags & 0x08) == 0 then
            outlineCornersOnly = (styleFlags & 2) ~= 0
        end
        styles[index] = {
            outlineColour = outlineColour,
            fillColour = fillColour,
            fill = fill,
            outlineCornersOnly = outlineCornersOnly,
            outlineThickness = thickness / 10,
        }
    end

    local labelledTiles = {}
    for _, tile in ipairs(tiles) do
        local metadata = readVaruint(reader)
        if metadata == nil then return nil, "Truncated preset token." end
        local styleIndex = metadata >> 1
        local style = styles[styleIndex + 1]
        if style == nil then return nil, "Invalid tile style index." end
        tile.outlineColour = style.outlineColour
        tile.fillColour = style.fillColour
        tile.fill = style.fill
        tile.outlineCornersOnly = style.outlineCornersOnly
        tile.outlineThickness = style.outlineThickness
        if (metadata & 1) ~= 0 then
            labelledTiles[#labelledTiles + 1] = tile
        end
    end

    if usesDictionary then
        local dictionaryCount = readVaruint(reader)
        if dictionaryCount == nil or dictionaryCount < 1
            or dictionaryCount > #labelledTiles then
            return nil, "Invalid label dictionary in preset token."
        end
        local dictionary = {}
        local previousDictionaryLabel = ""
        for index = 1, dictionaryCount do
            if usesPrefixDictionary then
                local prefixLength = readVaruint(reader)
                local suffixLength = readVaruint(reader)
                if prefixLength == nil or prefixLength > #previousDictionaryLabel
                    or suffixLength == nil
                    or prefixLength + suffixLength < 1
                    or prefixLength + suffixLength > MAX_LABEL_BYTES then
                    return nil, "Invalid tile label in preset token."
                end
                local suffix = readBytes(reader, suffixLength)
                if suffix == nil then
                    return nil, "Truncated preset token."
                end
                dictionary[index] = previousDictionaryLabel:sub(1, prefixLength) .. suffix
                previousDictionaryLabel = dictionary[index]
            else
                local labelLength = readVaruint(reader)
                if labelLength == nil or labelLength < 1 or labelLength > MAX_LABEL_BYTES then
                    return nil, "Invalid tile label in preset token."
                end
                dictionary[index] = readBytes(reader, labelLength)
                if dictionary[index] == nil then
                    return nil, "Truncated preset token."
                end
            end
        end
        for _, tile in ipairs(labelledTiles) do
            local labelIndex = readVaruint(reader)
            if labelIndex == nil or labelIndex >= dictionaryCount then
                return nil, "Invalid label dictionary index in preset token."
            end
            tile.label = dictionary[labelIndex + 1]
        end
    else
        for _, tile in ipairs(labelledTiles) do
            local labelLength = readVaruint(reader)
            if labelLength == nil or labelLength < 1 or labelLength > MAX_LABEL_BYTES then
                return nil, "Invalid tile label in preset token."
            end
            tile.label = readBytes(reader, labelLength)
            if tile.label == nil then
                return nil, "Truncated preset token."
            end
        end
    end

    if reader.position <= #reader.source then
        return nil, "Unexpected data at the end of preset token."
    end
    return { name = name, tiles = tiles }
end

return Codec
