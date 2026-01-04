local Memory = _imports.Memory
if Memory == nil then
	error("mkds_stuff needs memory imported! dofile \"pieces/memory.lua; _imports.Memory = _export\"")
end

local function FramesSinceRaceStart()
	-- Check if racer exists.
	local currentRacersPtr = memory.read_s32_le(Memory.addrs.ptrRacerData)
	if currentRacersPtr == 0 then
		return -1
	end

	-- Race won't begin until scene is running.
	local scenePtr = memory.read_u32_le(Memory.addrs.ptrSceneState)
	local sceneState = memory.read_u32_le(scenePtr + 0x10c)
	if sceneState < 2 or sceneState > 3 then
		return -1
	end
	
	-- Check if race has begun. (This static pointer points to junk on the main menu, which is why we checked racer data first.)
	return memory.read_s32_le(memory.read_s32_le(Memory.addrs.ptrRaceTimers) + 8)
end

_export = {
	FramesSinceRaceStart = FramesSinceRaceStart,
}