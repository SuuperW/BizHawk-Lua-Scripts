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
	return memory.read_u16_le_as_array(address, 4)
end

local function WriteSpriteData(spriteID, spriteData)
	local address = GetSpriteAddress(spriteID)
	memory.write_u16_le_as_array(address, spriteData)
end

local function GetSpritePosition(spriteData)
	return { spriteData[2] & 0xff, spriteData[1] & 0xff }
end
local function SetSpritePosition(spriteData, x, y)
	spriteData[1] = (spriteData[1] & 0xff00) | y
	spriteData[2] = (spriteData[2] & 0xfe00) | x
end

local function GetSpriteSrcTileX(spriteData)
	return spriteData[3] & 0x1f
end
local function GetSpriteSrcTileY(spriteData)
	return (spriteData[3] >> 5) & 0x1f
end
local function SetSpriteSrcTile(spriteData, x, y)
	spriteData[3] = (spriteData[3] & 0xfc00) | (y << 5) | x
end

local function GetSpriteColor(spriteData)
	return spriteData[3] >> 12
end
local function SetSpriteColor(spriteData, color)
	spriteData[3] = (spriteData[3] & 0x0fff) | (color << 12)
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

local function BytesTo32(tex)
	local n = {}
	for i = 1, #tex, 4 do
		n[#n+1] = tex[i] | (tex[i + 1] << 8) | (tex[i + 2] << 16) | (tex[i + 3] << 24)
	end
	return n
end

local function SetTileTextureTop(x, y, tex)
	local a = _baseTextureAddressTop + (x*0x20) + (y*0x400)
	local byteSize = 8 * 8 / 2
	local u32Size = 8 
	if #tex == byteSize then
		memory.write_u32_le_as_array(a, BytesTo32(tex))
	elseif #tex == u32Size then
		memory.write_u32_le_as_array(a, tex)
	else
		print("Invalid texture tile size given.")
	end
end
local function GetTileTextureTop(x, y)
	local a = _baseTextureAddressTop + (x*0x20) + (y*0x400)
	return memory.read_u32_le_as_array(a, 8)
end

local function SetTileTextureBottom(x, y, tex)
	local a = _baseTextureAddressBottom + (x*0x20) + (y*0x400)
	local byteSize = 8 * 8 / 2
	local u32Size = 8 
	if #tex == byteSize then
		memory.write_u32_le_as_array(a, BytesTo32(tex))
	elseif #tex == u32Size then
		memory.write_u32_le_as_array(a, tex)
	else
		print("Invalid texture tile size given.")
	end
end
local function GetTileTextureBottom(x, y)
	local a = _baseTextureAddressBottom + (x*0x20) + (y*0x400)
	return memory.read_u32_le_as_array(a, 8)
end

local function GetSpritePallet(id, top)
	local a = _basePalleteAddress + 0x200
	if not top then a = a + 0x400 end
	a =  a + 0x20 * id
	return memory.read_u16_le_as_array(a, 0x10)
end
local function SetSpritePallet(id, top, colors)
	local a = _basePalleteAddress + 0x200
	if not top then a = a + 0x400 end
	a = a + 0x20 * id
	if #colors == 0x20 then
		memory.write_u32_le_as_array(a, BytesTo32(colors))
	elseif #colors == 0x10 then
		memory.write_u16_le_as_array(a, colors)
	else
		print("Invalid colors")
	end
end

local function GetSpriteSize(spriteData)
	-- size is high 2 bits of [4]
	return spriteData[2] >> 14
end
local function SetSpriteSize(spriteData, size)
	spriteData[2] = (spriteData[2] & 0x3fff) | (size << 14)
end

local function BlankSprite()
	return { 0, 0, 0, 0 }
end

local function SetBlend(spriteData, blend)
	if blend then
		spriteData[1] = spriteData[1] | 0x0400
	else
		spriteData[1] = spriteData[1] & 0xfbff
	end
end
local function SetShape(spriteData, shape)
	spriteData[1] = (spriteData[1] & 0x3fff) | (shape << 14)
end
local function SetFlip(spriteData, flip)
	spriteData[2] = (spriteData[2] & 0xcfff) | (flip << 12)
end
local function SetPriority(spriteData, priority)
	spriteData[3] = (spriteData[3] & 0xf3ff) | (priority << 10)
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
