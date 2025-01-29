local Memory = _imports.Memory

local checkpointSize = 0x24;

local function getCheckpoints()
	local ptrCheckData = memory.read_s32_le(Memory.addrs.ptrCheckData)
	local totalcheckpoints = memory.read_u16_le(ptrCheckData + 0x48)
	if totalcheckpoints == 0 then return {} end
	local chkAddr = memory.read_u32_le(ptrCheckData + 0x44)

	local checkpointData = memory.read_bytes_as_array(chkAddr + 1, totalcheckpoints * checkpointSize)
	checkpointData[0] = memory.read_u8(chkAddr)

	local checkpoints = {}
	local testing = {}
	for i = 0, totalcheckpoints - 1 do
		-- CheckPoint X, Y for both end
		checkpoints[i] = {
			point1 = {
				Memory.get_s32(checkpointData, i * checkpointSize + 0x0),
				Memory.get_s32(checkpointData, i * checkpointSize + 0x4),
			},
			point2 = {
				Memory.get_s32(checkpointData, i * checkpointSize + 0x8),
				Memory.get_s32(checkpointData, i * checkpointSize + 0xC),
			},
			isFinish = false,
			isKey = Memory.get_s16(checkpointData, i * checkpointSize + 0x20) >= 0,
			nextChecks = { i + 1 },
		}
	end
	checkpoints[0].isFinish = true
	checkpoints.count = totalcheckpoints

	local pathsAddr = memory.read_u32_le(ptrCheckData + 0x4c)
	local pathsCount = memory.read_u32_le(ptrCheckData + 0x50)
	local pathSize = 0xC
	local pathsData = memory.read_bytes_as_array(pathsAddr + 1, pathsCount * pathSize - 1)
	pathsData[0] = memory.read_u8(pathsAddr)
	local paths = {}
	for i = 0, pathsCount - 1 do
		local p = i*pathSize
		paths[i] = {
			beginCheckId = Memory.get_u16(pathsData, p + 0),
			length = Memory.get_u16(pathsData, p + 2),
			nextPaths = { pathsData[p + 4], pathsData[p + 5], pathsData[p + 6] },
		}
	end
	for i = 0, pathsCount - 1 do
		local nextCpIds = {}
		for j = 1, #paths[i].nextPaths do
			local pid = paths[i].nextPaths[j]
			if pid ~= 0xff then
				nextCpIds[j] = paths[pid].beginCheckId
			end
		end
		checkpoints[paths[i].beginCheckId + paths[i].length - 1].nextChecks = nextCpIds
	end

	return checkpoints
end

_export = {
	getCheckpoints = getCheckpoints,
}