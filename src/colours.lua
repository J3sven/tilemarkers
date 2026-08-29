local Colours = {}

local PALETTE = {
    { name = "Cyan", rgb = 0x00FFFF },
    { name = "Red", rgb = 0xFF6464 },
    { name = "Green", rgb = 0x64FF64 },
    { name = "Yellow", rgb = 0xFFFF64 },
    { name = "Magenta", rgb = 0xFF96FF },
    { name = "Light Blue", rgb = 0x9696FF },
    { name = "Orange", rgb = 0xFFC864 },
    { name = "Purple", rgb = 0xC864FF },
}

Colours.DEFAULT_INDEX = 8

function Colours.normalize(index)
    index = math.floor(tonumber(index) or Colours.DEFAULT_INDEX)
    return math.max(1, math.min(#PALETTE, index))
end

function Colours.count()
    return #PALETTE
end

function Colours.name(index)
    return PALETTE[Colours.normalize(index)].name
end

function Colours.rgba(index, alpha)
    return (PALETTE[Colours.normalize(index)].rgb << 8) | (alpha & 0xFF)
end

function Colours.rgb(index)
    return PALETTE[Colours.normalize(index)].rgb
end

return Colours
