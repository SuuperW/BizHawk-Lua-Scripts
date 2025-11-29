_imports = {}

dofile "pieces/gpu2d.lua"
gpu2d = _export

dofile "pieces/memory.lua"
Memory = _export
_imports.Memory = Memory

dofile "pieces/mkds_stuff.lua"
mkdsstuff = _export

dofile "pieces/vectors.lua"
Vector = _export

local time_trial = false
local display_delay = 1

ts = {}
local function Test()
	local display_id = 0x50
	if #ts == 0 then
		-- for i = 0, 0x80, 2 do
		-- 	memory.write_u16_le(0x06400000 + 0x400*4 + i, 0)
		-- 	memory.write_u16_le(0x06400000 + 0x400*5 + i, 0)
		-- 	memory.write_u16_le(0x06400000 + 0x400*6 + i, 0)
		-- 	memory.write_u16_le(0x06400000 + 0x400*7 + i, 0)
		-- end
	end
	for i = 0, 3 do
		if ts[i] == nil then
			local sd = gpu2d.ReadSprite(display_id + i)
			-- sd[4] = 0
			-- sd[5] = 0
			-- sd[6] = 0
			-- sd[7] = 0
			-- sd[2] = 0
			gpu2d.SetSpritePosition(sd, 0x40 * i, 0x60 + 0 * i)
			gpu2d.SetSpriteSrcTile(sd, 8 * i, 0)
			gpu2d.SetSpriteColor(sd, 0)
			sd[4] = 0xc0
			sd[2] = 0 -- sd[2] & 0xfb --| 0x04
			ts[i] = sd
		end
		gpu2d.WriteSprite(display_id + i, ts[i])
	end
	--ts[3][2] = 4
end

local timerX = 179
local timerY = 4
local drawTIME = true
local moveLapCounter = true

-- Where in the top screen's texture image we can copy to.
local copyTexturesToX = 14
local copyTexturesToY = 0

memory.usememorydomain("ARM9 System Bus")

local spriteId = 0

local function MoveSpriteBy(id, x, y)
	local sd = gpu2d.ReadSprite(id)
	sd[1] = sd[1] + y
	sd[3] = sd[3] + x
	gpu2d.WriteSprite(id, sd)
end

local function AreTexturesSet()
	local tile = gpu2d.GetTileTextureTop(copyTexturesToX, copyTexturesToY)
	return tile[19] ~= 0
end

local function DrawTimer(x, y)
	-- Get color of timer
	local sprite0x80 = gpu2d.ReadSprite(0x80)
	local color = gpu2d.GetSpriteColor(sprite0x80)
	if color == 12 then
		color = 13 -- yellow
	elseif color == 13 then
		color = 14 -- red
	elseif color == 11 then
		color = 2 -- white
	end

	-- Draw text if desired
	if drawTIME then
		for i = 0, 1, 1 do
			local spriteData = gpu2d.ReadSprite(0x80 + i)
			local srcX = gpu2d.GetSpriteSrcTileX(spriteData)
			if (srcX >= 16) then -- TIME
				srcX = srcX + 2
				gpu2d.SetSpritePosition(spriteData, x-60 + i*32, y)
			elseif (srcX == 14) then -- LAP, only the second sprite is required
				srcX = -1
			else -- LAP sprite
				srcX = 14
				gpu2d.SetSpritePosition(spriteData, x - 44, y)
			end
			if (srcX ~= -1) then
				gpu2d.SetSpriteSrcTile(spriteData, srcX, 0)
				gpu2d.SetSpriteColor(spriteData, color)
				gpu2d.WriteSprite(spriteId, spriteData)
				spriteId = spriteId + 1
			end
		end
	end
	
	-- Draw digit sprites
	for i = 0, 7, 1 do
		local spriteData = gpu2d.ReadSprite(0x82 + i)
		gpu2d.SetSpritePosition(spriteData, x, y)
		x = x + 9
		local srcX = gpu2d.GetSpriteSrcTileX(spriteData)
		if (srcX == 22) then srcX = 10 end
        gpu2d.SetSpriteSrcTile(spriteData, srcX, 0)
		gpu2d.SetSpriteColor(spriteData, color)
		gpu2d.WriteSprite(spriteId, spriteData)
		spriteId = spriteId + 1
	end
end

local function FindLapCounter()
	local sid = 0
	local sd = gpu2d.ReadSprite(sid)
	while sd[5] ~= 88 do
		if sid > 80 then
			return nil
		end
		sid = sid + 1
		sd = gpu2d.ReadSprite(sid)
	end
	return sid
end
local function MoveLapCounter(sid)
	MoveSpriteBy(sid, 22, 17)
	sd = gpu2d.ReadSprite(sid + 1)
	if sd[5] == 27 then
		gpu2d.EraseSprite(sid + 1)
		gpu2d.EraseSprite(sid + 2)
	else
		MoveSpriteBy(sid + 1, 22, 17)
		gpu2d.EraseSprite(sid + 2)
		gpu2d.EraseSprite(sid + 3)
	end
end

local function RotateUnconvertedTexture(tex)
	local size = #tex

	local pixels = {}
	for i = 1, size do
		local rowPixels = {}
		for j = 0, size - 1 do
			rowPixels[#rowPixels+1] = (tex[i] >> ((size-1-j)*4)) & 0xf
		end
		pixels[i] = rowPixels
	end

	local rotated = {}
	for i = 1, size do rotated[i] = {} end
	for i = 1, size do
		for j = 1, size do
			rotated[i][j] = pixels[j][size-i+1]
		end
	end

	local newTex = {}
	for i = 1, size do
		local v = 0
		for j = 0, size-1 do
			v = v | (rotated[i][j+1] << ((size-1-j)*4))
		end
		newTex[i] = v
	end

	return newTex
end

local function WriteInputTextures()
	-- Enable blending
	memory.write_u16_le(0x04000050, 0x0140)
	-- Set blending alpha + sprite brightness
	memory.write_u16_le(0x04000052, 0x0b0f)

	local small_circle_texture = {
		0x00, 0x11, 0x11, 0x00,
		0x10, 0x22, 0x22, 0x01,
		0x21, 0x12, 0x21, 0x12,
		0x21, 0x11, 0x11, 0x12,
		0x21, 0x11, 0x11, 0x12,
		0x21, 0x12, 0x21, 0x12,
		0x10, 0x22, 0x22, 0x01,
		0x00, 0x11, 0x11, 0x00
	}
	local big_circle_texture = gpu2d.ConvertTextureBig({
		0x0000111100000000,
		--0x0123456789abcdef,
		0x0011222211000000,
		0x0122233222100000,
		0x0123333332100000,
		0x1223333332210000,
		0x1233333333210000,
		0x1233333333210000,
		0x1223333332210000,
		0x0123333332100000,
		0x0122233222100000,
		0x0011222211000000,
		0x0000111100000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000
	})
	local circle_tex_10px_outline = gpu2d.ConvertTextureBig({
		0x0001111000000000,
		0x0017777100000000,
		0x0170000710000000,
		0x1700000071000000,
		0x1700000071000000,
		0x1700000071000000,
		0x1700000071000000,
		0x0170000710000000,
		0x0017777100000000,
		0x0001111000000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000
	})
	gpu2d.SetTileTextureTop(0, 12, circle_tex_10px_outline[1])
	gpu2d.SetTileTextureTop(1, 12, circle_tex_10px_outline[2])
	gpu2d.SetTileTextureTop(0, 13, circle_tex_10px_outline[3])
	gpu2d.SetTileTextureTop(1, 13, circle_tex_10px_outline[4])
	local circle_tex_10px_pressed = gpu2d.ConvertTextureBig({
		0x0001111000000000,
		0x0017777100000000,
		0x0170000710000000,
		0x1700770071000000,
		0x1707777071000000,
		0x1707777071000000,
		0x1700770071000000,
		0x0170000710000000,
		0x0017777100000000,
		0x0001111000000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000,
		0x0000000000000000
	})
	gpu2d.SetTileTextureTop(2, 12, circle_tex_10px_pressed[1])
	gpu2d.SetTileTextureTop(3, 12, circle_tex_10px_pressed[2])
	gpu2d.SetTileTextureTop(2, 13, circle_tex_10px_pressed[3])
	gpu2d.SetTileTextureTop(3, 13, circle_tex_10px_pressed[4])
	local circle_tex_10px_unpressed = gpu2d.ConvertTextureSmall({
		0x01111000,
		0x11111100,
		0x11111100,
		0x11111100,
		0x11111100,
		0x01111000,
		0x00000000,
		0x00000000
	})
	gpu2d.SetTileTextureTop(4, 12, circle_tex_10px_unpressed)

	local shoulder_outline = gpu2d.ConvertTextureBig({
		0x0011111111111111,
		0x0177777777777777,
		0x1770000000000000,
		0x1700000000000000,
		0x1700000000000000,
		0x1770000000000000,
		0x0177777777777777,
		0x0011111111111111,
		0, 0, 0, 0, 0, 0, 0, 0
	})
	gpu2d.SetTileTextureTop(10, 12, shoulder_outline[1])
	gpu2d.SetTileTextureTop(11, 12, shoulder_outline[2])
	local shoulder_unpressed = gpu2d.ConvertTextureBig({
		0, 0,
		0x0001111111111111,
		0x0011111111111111,
		0x0011111111111111,
		0x0001111111111111,
		0, 0,
		0, 0, 0, 0, 0, 0, 0, 0
	})
	gpu2d.SetTileTextureTop(10, 13, shoulder_unpressed[1])
	gpu2d.SetTileTextureTop(11, 13, shoulder_unpressed[2])
	local shoulder_pressed = gpu2d.ConvertTextureBig({
		0, 0,
		0,
		0x0007777777777777,
		0x0007777777777777,
		0,
		0, 0,
		0, 0, 0, 0, 0, 0, 0, 0
	})
	gpu2d.SetTileTextureTop(10, 14, shoulder_pressed[1])
	gpu2d.SetTileTextureTop(11, 14, shoulder_pressed[2])

	local temp = {
		0x0001111100000000,
		0x0017777700000000,
		0x0177000000000000,
		0x0170000000000000,
		0x0170000000000000,
		0x0170000000000000,
		0x0170000000000000,
		0x0170000000000000,
		0x0170000000000000,
		0x0170000000000000,
		0x0170000000000000,
		0x0770000000000000,
		0,
		0,
		0,
		0,
	}
	local dpad_up_outline = gpu2d.ConvertTextureBig(temp)
	local dpad_right_outline = gpu2d.ConvertTextureBig(RotateUnconvertedTexture(temp))
	gpu2d.SetTileTextureTop(5, 12, dpad_up_outline[1])
	gpu2d.SetTileTextureTop(5, 13, dpad_up_outline[3])
	gpu2d.SetTileTextureTop(8, 12, dpad_right_outline[3])
	gpu2d.SetTileTextureTop(9, 12, dpad_right_outline[4])

	temp = {
		0x00111110,
		0x01111111,
		0x01111111,
		0x01111111,
		0x01111111,
		0x01111111,
		0x01111111,
		0x01111111,
		0x01111111,
		0x01111111,
		0x11111111,
		0x01111111,
		0x00111110,
		0x00011100,
		0,
		0,
	}
	local dpad_up_unpressed = gpu2d.ConvertTextureBig(temp)
	local dpad_right_unpressed = gpu2d.ConvertTextureBig(RotateUnconvertedTexture(temp))
	gpu2d.SetTileTextureTop(6, 12, dpad_up_unpressed[2])
	gpu2d.SetTileTextureTop(6, 13, dpad_up_unpressed[4])
	gpu2d.SetTileTextureTop(8, 13, dpad_right_unpressed[1])
	gpu2d.SetTileTextureTop(9, 13, dpad_right_unpressed[2])

	temp = {
		0x00000000,
		0x00077700,
		0x00777770,
		0x00777770,
		0x00777770,
		0x00777770,
		0x00777770,
		0x00777770,
		0x00777770,
		0x00777770,
		0x00777770,
		0x00777770,
		0x00777770,
		0x00077700,
		0,
		0,
	}
	local dpad_up_pressed = gpu2d.ConvertTextureBig(temp)
	local dpad_right_pressed = gpu2d.ConvertTextureBig(RotateUnconvertedTexture(temp))
	gpu2d.SetTileTextureTop(7, 12, dpad_up_pressed[2])
	gpu2d.SetTileTextureTop(7, 13, dpad_up_pressed[4])
	gpu2d.SetTileTextureTop(8, 14, dpad_right_pressed[1])
	gpu2d.SetTileTextureTop(9, 14, dpad_right_pressed[2])
end
local function WriteBoostTextures()
	local outline_start = gpu2d.ConvertTextureSmall{
		0,
		0x00001111,
		0x00017777,
		0x00170000,
		0x01700000,
		0x17000000,
		0x17777777,
		0x11111111,
	}
	local outline_end = gpu2d.ConvertTextureSmall{
		0,
		0x11111111,
		0x77777771,
		0x00000071,
		0x00007710,
		0x00077100,
		0x77771000,
		0x11110000,
	}
	local outline_middle = gpu2d.ConvertTextureSmall{
		0,
		0x11111111,
		0x77777777,
		0,
		0,
		0,
		0x77777777,
		0x11111111,
	}
	local empty = gpu2d.ConvertTextureSmall({
		0, 0, 0,
		0x11111111,
		0x11111111,
		0x11111111,
		0, 0,
	})
	local full = gpu2d.ConvertTextureSmall({
		0, 0, 0,
		0x22222222,
		0x22222222,
		0x22222222,
		0, 0,
	})
	gpu2d.SetTileTextureTop(0, 14, outline_start)
	gpu2d.SetTileTextureTop(1, 14, outline_middle)
	gpu2d.SetTileTextureTop(2, 14, outline_middle)
	gpu2d.SetTileTextureTop(3, 14, empty)
	gpu2d.SetTileTextureTop(4, 14, empty)
	gpu2d.SetTileTextureTop(5, 14, full)
	gpu2d.SetTileTextureTop(6, 14, full)

	-- color
	memory.write_u16_le(0x05000224, 0x1e | (0x1b << 5))

	local kmh1 = gpu2d.ConvertTextureBig({
		0, 0, 0, 0, 0,
		0x1111000000000000,
		0x1771000000000000,
		0x1771000000000000,
		0x1771111111111111,
		0x1771177117777777,
		0x1771771117777777,
		0x1777711017711711,
		0x1777771117711711,
		0x1771777117711711,
		0x1771177117711711,
		0x1111111111111111,
	})
	local kmh2 = gpu2d.ConvertTextureBig({
		0, 0, 0, 0, 0,
		0x0000011111111000,
		0x0000017711771000,
		0x0000017711771000,
		0x1100117111771111,
		0x7110177101777771,
		0x7710177101777777,
		0x7710177101771177,
		0x7711171101771177,
		0x7711771001771177,
		0x7711771001771177,
		0x1111111111111111,
	})
	local kmh3 = gpu2d.ConvertTextureSmall({
		0 << 28, 1 << 28, 1 << 28, 1 << 28,
		1 << 28, 1 << 28, 1 << 28, 1 << 28,
	})
	gpu2d.SetTileTextureTop(19, 10, kmh1[1])
	gpu2d.SetTileTextureTop(20, 10, kmh1[2])
	gpu2d.SetTileTextureTop(19, 11, kmh1[3])
	gpu2d.SetTileTextureTop(20, 11, kmh1[4])
	gpu2d.SetTileTextureTop(21, 10, kmh2[1])
	gpu2d.SetTileTextureTop(22, 10, kmh2[2])
	gpu2d.SetTileTextureTop(21, 11, kmh2[3])
	gpu2d.SetTileTextureTop(22, 11, kmh2[4])
	gpu2d.SetTileTextureTop(23, 11, kmh3)

	local dot = gpu2d.ConvertTextureSmall({
		0, 0, 0, 0,
		0x1111 << 12,
		0x1771 << 12,
		0x1771 << 12,
		0x1111 << 12,
	})
	gpu2d.SetTileTextureTop(0, 2, dot)

end

local function CopyTIME_LAP()
	for x = 0, 9 do
		for y = 0, 1 do
			local tex = gpu2d.GetTileTextureBottom(12 + x, 6 + y)
			gpu2d.SetTileTextureTop(copyTexturesToX + x, copyTexturesToY + y, tex)
		end
	end

	local colors = gpu2d.GetSpritePallet(13, false)
	gpu2d.SetSpritePallet(14, true, colors)
end

local function MakeSprite(x, y, tileX, tileY, color, size, shape, flips, blend, priority)
	local sprite = { 0, 0, 0, 0, 0, 0, 0, 0 }
	gpu2d.SetSpriteSrcTile(sprite, tileX, tileY)
	gpu2d.SetSpritePosition(sprite, x, y)
	gpu2d.SetSpriteColor(sprite, color)
	gpu2d.SetSpriteSize(sprite, size)
	if blend then
		sprite[2] = sprite[2] | 0x04
	end
	sprite[2] = sprite[2] | (shape << 6)
	sprite[4] = sprite[4] | (flips << 4)
	sprite[6] = sprite[6] | (priority << 2)

	gpu2d.WriteSprite(spriteId, sprite)
	spriteId = spriteId + 1
end

local function DrawInputs(x, y, inputs)
	local circleNames = { "A", "B", "X", "Y" }
	local circleLocations = {
		{ 18, 9 },
		{ 9, 18 },
		{ 9, 0 },
		{ 0, 9 }
	}

	for i = 1, 4 do
		circleLocations[i][1] = circleLocations[i][1] + x + 44
		circleLocations[i][2] = circleLocations[i][2] + y + 14

		if inputs[circleNames[i]] then
			MakeSprite(
				circleLocations[i][1] , circleLocations[i][2], 2, 12,
				2, 1, 0, 0, false, 0
			)
		else
			MakeSprite(
				circleLocations[i][1], circleLocations[i][2], 0, 12,
				2, 1, 0, 0, false, 0
			)
			MakeSprite(
				circleLocations[i][1] + 2, circleLocations[i][2] + 2, 4, 12,
				2, 0, 0, 0, true, 1
			)
		end
	end

	local shoulderNames = { "L", "R" }
	local shoulderLocations = {
		{ 4, 0 },
		{ 44, 0 }
	}

	for i = 1, 2 do
		shoulderLocations[i][1] = shoulderLocations[i][1] + x
		shoulderLocations[i][2] = shoulderLocations[i][2] + y

		MakeSprite(shoulderLocations[i][1], shoulderLocations[i][2], 10, 12,
			2, 0, 1, 0, false, 0)
		MakeSprite(shoulderLocations[i][1], shoulderLocations[i][2], 10, 13,
			2, 0, 1, 0, true, 1)
		MakeSprite(shoulderLocations[i][1] + 10, shoulderLocations[i][2], 10, 12,
			2, 0, 1, 1, false, 0)
		MakeSprite(shoulderLocations[i][1] + 10, shoulderLocations[i][2], 10, 13,
			2, 0, 1, 1, true, 1)
		if inputs[shoulderNames[i]] then
			MakeSprite(shoulderLocations[i][1], shoulderLocations[i][2], 10, 14,
				2, 0, 1, 0, false, 0)
			MakeSprite(shoulderLocations[i][1] + 10, shoulderLocations[i][2], 10, 14,
				2, 0, 1, 1, false, 0)
		end
	end

	local dpadNames = { "Left", "Up", "Right", "Down" }
	local dpadLocations = {
		{ 0, 15 },
		{ 10, 0 },
		{ 17, 15 },
		{ 10, 17 },
	}
	for i = 1, 4 do
		dpadLocations[i][1] = dpadLocations[i][1] + x + 0
		dpadLocations[i][2] = dpadLocations[i][2] + y + 12
	end

	-- center
	MakeSprite(
		dpadLocations[2][1] + 4, dpadLocations[1][2] - 2, 4, 12,
		2, 0, 0, 0, true, 2
	)

	-- up
	MakeSprite(dpadLocations[2][1], dpadLocations[2][2], 5, 12,
		2, 0, 2, 0, false, 0)
	MakeSprite(dpadLocations[2][1] + 5, dpadLocations[2][2], 5, 12,
		2, 0, 2, 1, false, 0)
	local srcX = 6
	local blend = true
	local priority = 1
	MakeSprite(dpadLocations[2][1] + 2, dpadLocations[2][2] + 2, srcX, 12,
		2, 0, 2, 0, blend, priority)
	if inputs["Up"] then
		srcX = 7
		blend = false
		priority = 0
		MakeSprite(dpadLocations[2][1] + 2, dpadLocations[2][2] + 2, srcX, 12,
			2, 0, 2, 0, blend, priority)
	end

	-- down
	MakeSprite(dpadLocations[4][1], dpadLocations[4][2], 5, 12,
		2, 0, 2, 2, false, 0)
	MakeSprite(dpadLocations[4][1] + 5, dpadLocations[4][2], 5, 12,
		2, 0, 2, 3, false, 0)
	srcX = 6
	blend = true
	priority = 1
	MakeSprite(dpadLocations[4][1] + 3, dpadLocations[4][2] - 2, srcX, 12,
		2, 0, 2, 3, blend, priority)
	if inputs["Down"] then
		srcX = 7
		blend = false
		priority = 0
		MakeSprite(dpadLocations[4][1] + 2, dpadLocations[4][2] - 2, srcX, 12,
			2, 0, 2, 2, blend, priority)
	end

	-- left
	MakeSprite(dpadLocations[1][1], dpadLocations[1][2], 8, 12,
		2, 0, 1, 0, false, 0)
	MakeSprite(dpadLocations[1][1], dpadLocations[1][2] - 5, 8, 12,
		2, 0, 1, 2, false, 0)
	local srcY = 13
	blend = true
	priority = 1
	MakeSprite(dpadLocations[1][1] + 2, dpadLocations[1][2] - 2, 8, srcY,
		2, 0, 1, 0, blend, priority)
	if inputs["Left"] then
		srcY = 14
		blend = false
		priority = 0
		MakeSprite(dpadLocations[1][1] + 2, dpadLocations[1][2] - 2, 8, srcY,
			2, 0, 1, 0, blend, priority)
	end

	-- right
	MakeSprite(dpadLocations[3][1], dpadLocations[3][2], 8, 12,
		2, 0, 1, 1, false, 0)
	MakeSprite(dpadLocations[3][1], dpadLocations[3][2] - 5, 8, 12,
		2, 0, 1, 3, false, 0)
	srcY = 13
	blend = true
	priority = 1
	MakeSprite(dpadLocations[3][1] - 2, dpadLocations[3][2] - 3, 8, srcY,
		2, 0, 1, 3, blend, priority)
	if inputs["Right"] then
		srcY = 14
		blend = false
		priority = 0
		MakeSprite(dpadLocations[3][1] - 2, dpadLocations[3][2] - 2, 8, srcY,
			2, 0, 1, 1, blend, priority)
	end
end

local function DrawBoostIndicator(x, y, prb, time)
	MakeSprite(x, y, 0, 14,
		2, 0, 0, 0, false, 0)
	for i = 0, 4 do
		MakeSprite(x+8 + 16*i, y, 1, 14,
			2, 0, 1, 0, false, 0)
	end
	MakeSprite(x + 86, y + 1, 0, 14,
		2, 0, 0, 3, false, 0)

	x = x + 2

	local color = 1
	if prb then color = 2 end

	-- empty fill at the end
	if time < 90 then
		MakeSprite(x + 90 - 16, y, 3, 14,
			2, 0, 1, 0, true, 2)
	end

	local srcX = 5
	local blend = false
	local boostPriority = 2
	local emptyPriority = 1
	for i = 0, 4 do
		if time < 16 then
			local extendedX = 16*i + time
			if extendedX > 90 - 16 then extendedX = 90 - 16 end
			MakeSprite(x + extendedX, y, 3, 14,
				2, 0, 1, 0, true, emptyPriority)
		end
		local boostX = 16*i
		if i > 0 and time > 0 and time < 16 then
			boostX = boostX - (16 - time)
		end
		MakeSprite(x + boostX, y, srcX, 14,
			color, 0, 1, 0, blend, boostPriority)
		time = time - 16
		if time <= 0 then
			srcX = 3
			blend = true
			color = 2
		end

		boostPriority = 1
		emptyPriority = 2
	end
	if time > 0 then
		local extendedX = 16*5 + time
		if extendedX > 90 then extendedX = 90 end
		extendedX = extendedX - 16
		MakeSprite(x + extendedX, y, srcX, 14,
			color, 0, 1, 0, blend, boostPriority)
	end
end

local function DrawSpeedometer(x, y, speed)
	speed = string.format("%.1f", math.abs(speed))
	local scale = client.bufferwidth() / 256

	local maxlen = 5
	speed_str = (string.rep(" ", maxlen) .. tostring(speed)):sub(-maxlen,-1)
	for i = 1, maxlen do
		local char = string.sub(speed_str, i, i)
		if char == "." then
			MakeSprite(x, y+8, 0, 2,
				2, 0, 0, 0, false, 0)
			x = x - 2
		elseif char ~= " " then
			local digit = tonumber(char)
			MakeSprite(x, y, digit, 0,
				2, 0, 2, 0, false, 0)
		end
		x = x + 9
	end
	
	x = x + 2
	MakeSprite(x, y, 19, 10,
		2, 2, 1, 0, false, 0)
	MakeSprite(x+32, y+8, 23, 11,
		2, 0, 0, 0, false, 0)
end

local function GetSpeed(racerPtr)
	-- There isn't really any good in-game value.
	-- We have these values in-game:
	-- 1) position at 0x80, vector
	-- 2) lastPosition at 0x8C, vector
	-- 3) basePosDeltaMag at 0x2a4, scalar
		-- This is 3D and includes motion into the ground while on ground. Fluctates when hopping.
		-- It also does not include collision pushes, so it won't match actual movement speed on slopes.
	-- 4) speed at 0x2a8, scalar
		-- Just the base speed value, wildly inaccurate in certain situatinos.
	
	-- I also don't see a really great way to calculate a speed value. I'll use two different methods here:
	-- A) While on the ground, take difference of position.
	-- B) While in the air, subtract vertical speed. This should keep speed steady while hopping.
		-- Once we exceed 13 air frames, ignore Y position.
		-- It's not great, but for large jumps the old surface normal really isn't relevant anymore.
	local posDelta = Vector.subtract(Memory.read_pos(racerPtr + 0x80), Memory.read_pos(racerPtr + 0x8C))
	local airtime = memory.read_u32_le(racerPtr + 0x380)
	if airtime > 13 then
		posDelta[2] = 0
	elseif airtime > 0 then
		posDelta[2] = posDelta[2] - memory.read_s32_le(racerPtr + 0x260)
	end

	return Vector.getMagnitude(posDelta) * 0x1000 / 360
	-- Times 0x1000 converts it back to subunits.
	-- Divide by 360 is just convention for HUD speedometers.
end

local lastInputs = {}
local lastHud = {}
local function OnFrame()
	memory.usememorydomain("ARM9 System Bus")
	
	if mkdsstuff.FramesSinceRaceStart() > 0 then
		local lapid = FindLapCounter()
		if lapid ~= nil then
			gpu2d.RemoveRedundantSprites(false)
			lapid = FindLapCounter()

			spriteId = gpu2d.FirstAvailableSpriteTop()
			-- why does this one exist?
			gpu2d.EraseSprite(lapid - 1)
			
			if not AreTexturesSet() then
				CopyTIME_LAP()
				WriteInputTextures()
				WriteBoostTextures()
			end

			local racerPtr = memory.read_u32_le(Memory.addrs.ptrRacerData)
			local boostTime = memory.read_u8(racerPtr + 0x238)
			local prb = (memory.read_u8(racerPtr + 0x4B) & 0x20) ~= 0
			local speed = GetSpeed(racerPtr)

			DrawTimer(timerX, timerY)
			local firstSpriteIdAfterTimer = spriteId
			if moveLapCounter then MoveLapCounter(lapid) end
			DrawInputs(4, 140, lastInputs)
			DrawBoostIndicator(158, 180, prb, boostTime)
			DrawSpeedometer(173, 162, speed)
			--Test()

			-- The HUD should show what was pressed, while getwithmovie tells what is being held for the upcoming frame.
			lastInputs = joypad.getwithmovie()

			if display_delay > 0 then
				local count = 0x80 - firstSpriteIdAfterTimer
				lastHud[#lastHud + 1] = memory.read_bytes_as_array(0x07004000 + 8 * firstSpriteIdAfterTimer, 8 * count)
				if #lastHud > display_delay then
					memory.write_bytes_as_array(0x07004000 + 8 * firstSpriteIdAfterTimer, lastHud[1])
					for i = (#lastHud[1] / 8) + firstSpriteIdAfterTimer, 0x7f do
						memory.write_bytes_as_array(0x07004000 + i*8, {0,0,0,0,0,0,0,0})
					end
					for i = 1, display_delay do
						lastHud[i] = lastHud[i + 1]
					end
					lastHud[display_delay + 1] = nil
				else
					for i = firstSpriteIdAfterTimer, 0x7f do
						memory.write_bytes_as_array(0x07004000 + i*8, {0,0,0,0,0,0,0,0})
					end
				end
			end

			if spriteId >= 0x80 then
				error("Exceeded maximum sprite count.")
			end
		end
	end
end
while true do
	OnFrame()
	emu.frameadvance()
end
