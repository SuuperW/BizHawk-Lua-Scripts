--local Memory = _imports.Memory

local _baseSpriteAddress        = 0x07004000
local _baseTextureAddressTop    = 0x06400000
local _baseTextureAddressBottom = 0x06600000
local _basePalleteAddress       = 0x05000000

local SHAPE = {}
SHAPE.NORMAL = 0
SHAPE.WIDE = 1
SHAPE.TALL = 2

local FLIP = {}
FLIP.NONE = 0
FLIP.HORIZONTAL = 1
FLIP.VERTICAL = 2
FLIP.BOTH = 3

local function GetSpriteAddress(spriteID)
	if spriteID == nil then print(debug.traceback()) end

	local address = _baseSpriteAddress + spriteID * 8
	return address
end
local function ReadSpriteData(spriteID)
	local address = GetSpriteAddress(spriteID)
	return memory.read_bytes_as_array(address, 8)
end

local function WriteSpriteData(spriteID, spriteData)
	local address = GetSpriteAddress(spriteID)
	memory.write_bytes_as_array(address, spriteData)
end

local function GetSpritePosition(spriteData)
	return { spriteData[3], spriteData[1] }
end
local function SetSpritePosition(spriteData, x, y)
	spriteData[1] = y
	spriteData[3] = x
end

local function GetSpriteSrcTileX(spriteData)
	-- srcTileX is the low 5 bits of spriteData[5]
	return spriteData[5] & 0x1f
end
local function GetSpriteSrcTileY(spriteData)
	-- srcTileX is the low 5 bits of spriteData[5]
	-- srcTileY is the next 5 bits
	local srcAs16bit = spriteData[5] & (spriteData[6] << 8)
	return (srcAs16bit >> 5) & 0x1f
end
local function SetSpriteSrcTile(spriteData, x, y)
	-- srcTileX is the low 5 bits of spriteData[5]
	-- srcTileY is the next 5 bits
	spriteData[5] = ((y & 7) << 5) | x
	spriteData[6] = (spriteData[6] & 0xfc) | (y >> 3)
end

local function GetSpriteColor(spriteData)
	-- color is the high 4 bits of spriteData[6]
	return spriteData[6] >> 4
end
local function SetSpriteColor(spriteData, color)
	-- color is the high 4 bits of spriteData[6]
	spriteData[6] = (spriteData[6] & 0x0f) | (color << 4)
end

local function EraseSprite(id)
	local address = GetSpriteAddress(id)
	memory.write_u16_le(address, 0x00C0)
end

local function FirstAvailableSpriteTop()
	local a = _baseSpriteAddress
	for i = 0, 0x7f do
		if memory.read_u16_le(a) == 0x00C0 then
			return i
		end
		a = a + 8
	end
	return nil
end
local function FirstAvailableSpriteBottom()
	local a = _baseSpriteAddress + 0x80 * 8
	for i = 0x80, 0xff do
		if memory.read_u16_le(a) == 0xC0C0 then
			return i
		end
		a = a + 8
	end
	return nil
end

local function RemoveRedundantSprites(time_trial)
	-- The item HUD is sooooo bad.
	-- We could do more if we did more than just erase.

	local last = FirstAvailableSpriteTop() - 1
	local sourceIndex = 17
	local destIndex = 9
	while destIndex <= last do
		local sd = ReadSpriteData(sourceIndex)
		WriteSpriteData(destIndex, sd)

		sourceIndex = sourceIndex + 1
		destIndex = destIndex + 1

		if time_trial and sourceIndex == 26 then
			sourceIndex = 31
		end
	end
end

local function ConvertTextureBig(tex)
	local newtex = {}
	local bytes = {}
	for i = 1, #tex do
		for j = 0, 7 do
			local b = (tex[i] >> ((7-j)*8)) & 0xff
			bytes[#bytes + 1] = ((b & 0xf) << 4) | ((b & 0xf0) >> 4)
		end
	end
	
	local tiles = {{}, {}, {}, {}}
	for y = 0, 7 do
		for x = 0, 3 do
			tiles[1][#tiles[1] + 1] = bytes[x + y*8 + 1]
			tiles[2][#tiles[2] + 1] = bytes[x+4 + y*8 + 1]
			tiles[3][#tiles[3] + 1] = bytes[x + (y+8)*8 + 1]
			tiles[4][#tiles[4] + 1] = bytes[x+4 + (y+8)*8 + 1]
		end
	end
	
	return tiles
end
local function ConvertTextureSmall(tex)
	local newtex = {}
	local bytes = {}
	for i = 1, #tex do
		for j = 0, 3 do
			local b = (tex[i] >> ((3-j)*8)) & 0xff
			bytes[#bytes + 1] = ((b & 0xf) << 4) | ((b & 0xf0) >> 4)
		end
	end
	
	return bytes
end

local function SetTileTextureTop(x, y, tex)
	local byteSize = 8 * 8 / 2
	if #tex ~= byteSize then
		print("Invalid texture tile size given.")
		return
	end
	local a = _baseTextureAddressTop + (x*0x20) + (y*0x400)
	memory.write_bytes_as_array(a, tex)
end
local function GetTileTextureTop(x, y)
	local a = _baseTextureAddressTop + (x*0x20) + (y*0x400)
	return memory.read_bytes_as_array(a, 0x20)
end

local function SetTileTextureBottom(x, y, tex)
	local byteSize = 8 * 8 / 2
	if #tex ~= byteSize then
		print("Invalid texture tile size given.")
		return
	end
	local a = _baseTextureAddressBottom + (x*0x20) + (y*0x400)
	memory.write_bytes_as_array(a, tex)
end
local function GetTileTextureBottom(x, y)
	local a = _baseTextureAddressBottom + (x*0x20) + (y*0x400)
	return memory.read_bytes_as_array(a, 0x20)
end

local function GetSpritePallet(id, top)
	local a = _basePalleteAddress + 0x200
	if not top then a = a + 0x400 end
	a =  a + 0x20 * id
	return memory.read_bytes_as_array(a, 0x20)
end
local function SetSpritePallet(id, top, colors)
	local a = _basePalleteAddress + 0x200
	if not top then a = a + 0x400 end
	a = a + 0x20 * id
	if #colors == 0x20 then
		memory.write_bytes_as_array(a, colors)
	elseif #colors == 0x10 then
		for i = 1, 16 do
			memory.write_u16_le(a + i*2, colors[i])
		end
	else
		print("Invalid colors")
	end
end

local function GetSpriteSize(spriteData)
	-- size is high 2 bits of [4]
	return spriteData[4] >> 6
end
local function SetSpriteSize(spriteData, size)
	spriteData[4] = (spriteData[4] & 0x3f) | (size << 6)
end

local function BlankSprite()
	return { 0, 0, 0, 0, 0, 0, 0, 0 }
end

local function SetBlend(spriteData, blend)
	if blend then
		spriteData[2] = spriteData[2] | 0x04
	else
		spriteData[2] = spriteData[2] & 0xfb
	end
end
local function SetShape(spriteData, shape)
	spriteData[2] = (spriteData[2] & 0x3f) | (shape << 6)
end
local function SetFlip(spriteData, flip)
	spriteData[4] = (spriteData[4] & 0xcf) | (flip << 4)
end
local function SetPriority(spriteData, priority)
	spriteData[6] = (spriteData[6] & 0xf3) | (priority << 2)
end

_export = {
	ReadSprite = ReadSpriteData,
	WriteSprite = WriteSpriteData,
	GetSpritePosition = GetSpritePosition,
	SetSpritePosition = SetSpritePosition,
	GetSpriteSrcTileX = GetSpriteSrcTileX,
	GetSpriteSrcTileY = GetSpriteSrcTileY,
	SetSpriteSrcTile = SetSpriteSrcTile,
	GetSpriteColor = GetSpriteColor,
	SetSpriteColor = SetSpriteColor,
	EraseSprite = EraseSprite,
	ConvertTextureBig = ConvertTextureBig,
	ConvertTextureSmall = ConvertTextureSmall,
	SetTileTextureTop = SetTileTextureTop,
	GetTileTextureTop = GetTileTextureTop,
	SetTileTextureBottom = SetTileTextureBottom,
	GetTileTextureBottom = GetTileTextureBottom,
	FirstAvailableSpriteBottom = FirstAvailableSpriteBottom,
	FirstAvailableSpriteTop = FirstAvailableSpriteTop,
	GetSpritePallet = GetSpritePallet,
	SetSpritePallet = SetSpritePallet,
	GetSpriteSize = GetSpriteSize,
	SetSpriteSize = SetSpriteSize,
	RemoveRedundantSprites = RemoveRedundantSprites,
	BlankSprite = BlankSprite,
	SetBlend = SetBlend,
	SetShape = SetShape,
	SetFlip = SetFlip,
	SetPriority = SetPriority,
	
	SHAPE = SHAPE,
	FLIP = FLIP,
}
