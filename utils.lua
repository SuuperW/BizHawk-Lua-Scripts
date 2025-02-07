-- Some useful things and some hacks, to be used manually in the Lua Console.

function GetRacerPtr(id)
	local racer = memory.read_u32_le(0x0217ACF8)
	return racer + id*0x5a8
end

function ReadRacer(id, offset)
	local racer = GetRacerPtr(id)
	return memory.read_u32_le(racer + offset)
end

function MakeGhostCollidable()
	local player = GetRacerPtr(0)
	local ghost = GetRacerPtr(1)
	local f7c = memory.read_u32_le(ghost + 0x7c)
	memory.write_u32_le(ghost + 0x7c, f7c & ~0x8000004)
	f7c = memory.read_u32_le(player + 0x7c)
	memory.write_u32_le(player + 0x7c, f7c & ~0x8000004)
end

function FinishRace()
	local ptr = memory.read_u32_le(0x021755FC)

	-- End the race
	memory.write_u16_le(ptr + 0xE, 8)
	memory.write_u8(ptr + 0x14, 1)

	-- Update finish time
	local lap = memory.read_s8(ptr + 0x38) - 1
	if lap < 0 then lap = 0 end
	if lap > 4 then lap = 4 end
	local currentLapFrames = memory.read_s32_le(ptr + 0x18)
	local ssf = currentLapFrames % 60
	local ms = ssf * 1000 // 60
	local seconds = (currentLapFrames - ssf) // 60
	local minutes = (currentLapFrames - 60*seconds - ssf) // 3600

	local lapTimeCombined = (seconds << 24) | (minutes << 16) | ms
	memory.write_u32_le(ptr + 0x20 + lap*4, lapTimeCombined)
	local totalTimeCombined = memory.read_u32_le(ptr + 0x34)
	local totalMs = (totalTimeCombined & 0xffff) + ms
	local totalSeconds = (totalTimeCombined >> 24) + seconds
	local totalMinutes = ((totalTimeCombined >> 16) & 0xff) + minutes
	if totalMs >= 1000 then
		totalMs = totalMs - 1000
		totalSeconds = totalSeconds + 1
	end
	if totalSeconds >= 60 then
		totalSeconds = totalSeconds - 60
		totalMinutes = totalMinutes + 1
	end
	totalTimeCombined = (totalSeconds << 24) | (totalMinutes << 16) | totalMs
	memory.write_u32_le(ptr + 0x34, totalTimeCombined)

	-- Update recorded inputs count
	ptr = memory.read_s32_le(0x02175630)
	memory.write_s32_le(ptr, 1765) -- max input count for ghost
end

function GiveItem(racer, item)
	local itemPtr = memory.read_s32_le(0x0217BC2C)
	itemPtr = itemPtr + 0x210*racer
	memory.write_u8(itemPtr + 0x4c, item)
end

print("Loaded utils.")