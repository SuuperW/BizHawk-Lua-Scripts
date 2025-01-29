-- Authors: Suuper; some checkpoint and pointer stuffs from MKDasher
-- Also a thanks to the HaroohiePals team for figuring out some data structure things
-- A Lua script that aims to be helpful for creating tool-assisted speedruns.

-- Script options ---------------------
-- These are the default values. If you have a MKDS_Info-Config.txt file then config settings will be read from that file.
-- If you don't have this file, it will be created for you.
local config = {
	-- display options
	defaultScale = 0.8, -- big = zoom out
	increaseRenderDistance = false, -- true to draw triangels far away (laggy)
	renderAllTriangles = false,
	objectRenderDistance = 600,
	showExactMovement = true, -- true: dispaly fixed-point values as integers (0-4096 for 0.0-1.0)
	showAnglesAsDegrees = false,
	showBottomScreenInfo = true,
	-- behavior
	alertOnRewindAfterBranch = true, -- BizHawk simply does not support nice seeking behavior, so we can't do it for you.
	ancientStateInterval = 500, -- Workaround for BizHawk 2.10 bug that makes ancient states not work.
	showBizHawkDumbnessWarning = true,

	-- hacks: use these with caution as they can desync a movie or mess up state hisotry
	enableCameraFocusHack = false,
	giveGhostShrooms = false, -- for testing
}

local optionsFromFile = {}
local function writeConfig(exclude)
	configFile = io.open("MKDS_Info_Config.txt", "a")
	if configFile == nil then error("could not write config") end
	for k, v in pairs(config) do
		if exclude[k] == nil then
			configFile:write(k .. " ")
			if type(v) == "number" then
				configFile:write(v)
			elseif type(v) == "boolean" then
				if v == true then configFile:write("true") else configFile:write("false") end
			else
				io.close(configFile)
				error("invalid value in config for " .. k)
			end
			configFile:write("\n")
		end
	end
	io.close(configFile)

end
local function readConfig()
	local configFile = io.open("MKDS_Info_Config.txt", "r")
	if configFile == nil then
		writeConfig({})
		return
	end

	local keysRead = {}
	for line in configFile:lines() do
		local index = string.find(line, " ")
		local name = string.sub(line, 0, index - 1)
		local value = string.sub(line, index + 1)
		if value == "true" then value = true
		elseif value == "false" then value = false
		else value = tonumber(value)
		end
		config[name] = value
		keysRead[name] = true
	end
	writeConfig(keysRead)
	io.close(configFile)
end
readConfig()

---------------------------------------
config.defaultScale = 0x1000 * config.defaultScale / client.getwindowsize() -- "windowsize" is the scale factor
config.objectRenderDistance = config.objectRenderDistance * config.objectRenderDistance * 0x1000000
---------------------------------------

local bizhawkVersion = client.getversion()
if string.sub(bizhawkVersion, 0, 3) == "2.9" then
	bizhawkVersion = 9
elseif string.sub(bizhawkVersion, 0, 4) == "2.10" then
	bizhawkVersion = 10
else
	bizhawkVersion = 0
	print("You're using an unspported version of BizHawk.")
end

-- I've split this file into multiple files to keep it more organized.
-- Unfortunately, BizHawk doesn't give each Lua script it's own environment and using require does not work nicely or reliably.
-- I am using dofile instead.
-- However, I also would like to keep distribution simple by keeping the distributed version as a single file.
-- So, I will create a Python script that "builds" it into one script. Each file that is to be run with dofile will be
--     placed into a function (so that it has its own scope, mimcing dofile). The files will "export" an object by
--     setting the global _export. This script will then "import" it by assigning that object to a local.
_imports = {} -- Some files may require things from us.
dofile "pieces/vectors.lua"
local Vector = _export
_imports.Vector = Vector

dofile "pieces/memory.lua"
local Memory = _export
_imports.Memory = Memory
local get_u32 = Memory.get_u32
local get_s32 = Memory.get_s32
local get_s16 = Memory.get_s16
local get_pos = Memory.get_pos
local get_quaternion = Memory.get_quaternion
local read_pos = Memory.read_pos

dofile "pieces/kcl.lua"
local KCL = _export
_imports.KCL = KCL

dofile "pieces/objects.lua"
local Objects = _export
_imports.Objects = Objects

dofile "pieces/graphics.lua"
local Graphics = _export

dofile "pieces/checkpoiunts.lua"
local Checkpoints = _export

-- BizHawk shenanigans
if script_id == nil then
	script_id = 1
else
	script_id = script_id + 1
end
local frame = emu.framecount()
local lastFrame = 0
local my_script_id = script_id
local shouldExit = false
local redrawSeek = nil

-- Some stuff
local function NewMyData()
	local n = {}
	n.positionDelta = 0
	n.angleDelta = 0
	n.driftAngleDelta = 0
	n.pos = Vector.zero()
	n.facingAngle = 0
	n.driftAngle = 0
	n.movementDirection = Vector.zero()
	n.movementTarget = Vector.zero()
	n.hitboxType = "spherical"
	return n
end
local myData = NewMyData()
local allRacers = {}
local racerCount = 0

local raceData = {}

local form = {}
local watchingId = 0
local drawWhileUnpaused = true
local course = {}

local function clearDataOutsideRace()
	raceData = {
		coinsBeingCollected = 0,
	}
	allRacers = {}
	form.ghostInputs = nil
	forms.settext(form.ghostInputHackButton, "Copy from player")
	course = {}
end

-- General stuffs -------------------------------
local satr = 2 * math.pi / 0x10000

function contains(list, x)
	for _, v in ipairs(list) do
		if v == x then return true end
	end
	return false
end
function copyTableShallow(table)
	local new = {}
	for k, v in pairs(table) do
		new[k] = v
	end
	return new
end
function removeItem(_table, item)
	for i, v in ipairs(_table) do
		if v == item then
			table.remove(_table, i)
			return true
		end
	end
	return false
end

local function normalizeQuaternion_float(v)
	local m = math.sqrt(v.i * v.i + v.j * v.j + v.k * v.k + v.r * v.r) / 0x1000
	return {
		i = v.i / m,
		j = v.j / m,
		k = v.k / m,
		r = v.r / m,
	}
end
local function quaternionAngle(q)
	q = normalizeQuaternion_float(q)
	return math.floor(math.acos(q.r / 4096) * 0x10000 / math.pi)
end

-- String formattings. https://cplusplus.com/reference/cstdio/printf/
local sem = config.showExactMovement
local smf = not sem
local function format01(value)
	-- Format a value expected to be between 0 and 1 (4096) based on script settings.
	if smf then
		return string.format("%6.3f", value)
	else
		return value
	end
end
local function posVecToStr(vector, prefix)
	return string.format("%s%9i, %9i, %8i", prefix, vector[1], vector[3], vector[2])
end
local function normalVectorToStr(vector, prefix)
	if sem then
		return string.format("%s%5i, %5i, %5i", prefix, vector[1], vector[3], vector[2])
	else
		return string.format("%s%6.3f, %6.3f, %6.3f", prefix, vector[1] / 0x1000, vector[3] / 0x1000, vector[2] / 0x1000)
	end
end
local function rawQuaternion(q, prefix)
	return string.format("%s%4i %4i %4i %4i", prefix, q.k, q.j, q.i, q.r)
end
-------------------------------------------------

-- MKDS -----------------------------------------
local triangles = nil

local nearbyObjects = nil

local checkpoints = {}

local ptrRacerData = nil
local ptrCheckNum = nil
local ptrRaceTimers = nil
local ptrMissionInfo = nil

local gameCameraHisotry = {{},{},{}}
local drawingPackages = {}

local function getRacerBasicData(ptr, previousData)
	local newData = NewMyData()
	newData.ptr = ptr
	if ptr == 0 then
		return newData
	end

	newData.posForObjects = read_pos(ptr + 0x1b8)
	newData.posForItems = read_pos(ptr + 0x1d8)
	newData.radius = memory.read_s32_le(ptr + 0x1d0)
	newData.movementDirection = read_pos(ptr + 0x68)
	if previousData ~= nil then
		newData.real2dSpeed = math.sqrt((previousData.pos[3] - newData.pos[3]) ^ 2 + (previousData.pos[1] - newData.pos[1]) ^ 2)
		newData.actualPosDelta = Vector.subtract(newData.pos, previousData.pos)
		newData.facingDelta = newData.facingAngle - previousData.facingAngle
		newData.driftDelta = newData.driftAngle - previousData.driftAngle
	end

	return newData
end
local function getRacerDetails(ptr, previousData, isSameFrame)
	local newData = NewMyData()
	newData.ptr = ptr
	if ptr == 0 then
		return newData
	end

	-- Optimization: Do only one BizHawk API call. Yes, this is a little faster.
	-- Off-by-one shenanigans because Lua table indexes are 1-based by default.
	-- Also things not in use are commented out.
	local allData = memory.read_bytes_as_array(ptr + 1, 0x5a8 - 1)
	--allData[0] = memory.read_u8(ptr)

	-- Read positions and speed
	newData.pos = get_pos(allData, 0x80)
	newData.posForObjects = get_pos(allData, 0x1B8) -- also used for collision
	newData.preMovementPosForObjects = get_pos(allData, 0x1C4) -- this too is used for collision
	newData.posForItems = get_pos(allData, 0x1D8) -- also for racer-racer collision
	newData.speed = get_s32(allData, 0x2A8)
	newData.basePosDelta = get_pos(allData, 0xA4)
	newData.boostAll = allData[0x238]
	newData.boostMt = allData[0x23C]
	newData.verticalVelocity = get_s32(allData, 0x260)
	newData.mtTime = get_s32(allData, 0x30C)
	newData.maxSpeed = get_s32(allData, 0xD0)
	newData.turnLoss = get_s32(allData, 0x2D4)
	newData.offroadSpeed = get_s32(allData, 0xDC)
	newData.wallSpeedMult = get_s32(allData, 0x38C)
	newData.airSpeed = get_s32(allData, 0x3F8)
	newData.effectSpeed = get_s32(allData, 0x394)
	
	-- angles
	newData.facingAngle = get_s16(allData, 0x236)
	newData.pitch = get_s16(allData, 0x234)
	newData.driftAngle = get_s16(allData, 0x388)
	--newData.wideDrift = get_s16(allData, 0x38A) -- Controls tightness of drift when pressing outside direction, and rate of drift air spin.
	newData.movementDirection = get_pos(allData, 0x68)
	newData.movementTarget = get_pos(allData, 0x50)
	--newData.targetMovementVectorSigned = get_pos(allData, 0x5c)
	newData.snQuaternion = get_quaternion(allData, 0xf0)
	newData.snqTarget = get_quaternion(allData, 0x100)
	--newData.faQuaternion = get_quaternion(allData, 0xe0)
	--newData.facingQuatenion = get_quaternion(allData, 0x110)

	-- Real speed
	if isSameFrame then
		newData.real2dSpeed = previousData.real2dSpeed
		newData.actualPosDelta = previousData.actualPosDelta
		newData.facingDelta = previousData.facingDelta
		newData.driftDelta = previousData.driftDelta
	else
		newData.real2dSpeed = math.sqrt((previousData.pos[3] - newData.pos[3]) ^ 2 + (previousData.pos[1] - newData.pos[1]) ^ 2)
		newData.actualPosDelta = Vector.subtract(newData.pos, previousData.pos)
		newData.facingDelta = newData.facingAngle - previousData.facingAngle
		newData.driftDelta = newData.driftAngle - previousData.driftAngle
	end
	newData.collisionPush = Vector.subtract(newData.actualPosDelta, newData.basePosDelta)

	-- surface/collision stuffs
	newData.surfaceNormalVector = get_pos(allData, 0x244)
	newData.grip = get_s32(allData, 0x240)
	newData.radius = get_s32(allData, 0x1d0)
	--newData.radiusMult = get_s32(allData, 0x4c8)

	-- status things
	newData.framesInAir = get_s32(allData, 0x380)
	if allData[0x3DD] == 0 then
		newData.air = "Ground"
	else
		newData.air = "Air"
	end
	newData.spawnPoint = get_s32(allData, 0x3C4)
	newData.flags44 = get_u32(allData, 0x44)
	
	-- extra movement
	newData.movementAdd1fc = get_pos(allData, 0x1fc)
	newData.movementAdd2f0 = get_pos(allData, 0x2f0)
	newData.movementAdd374 = get_pos(allData, 0x374)
	--newData.tb = get_pos(allData, 0x2d8)
	newData.waterfallPush = get_pos(allData, 0x268)
	newData.waterfallStrength = get_s32(allData, 0x274)

	-- Rank/score
	--local ptrScoreCounters = memory.read_s32_le(Memory.addrs.ptrScoreCounters)
	--newData.wallHitCount = memory.read_s32_le(ptrScoreCounters + 0x10)
	
	-- ?	
	--newData.smsm = get_s32(allData, 0x39c)
	--newData.statsPtr = get_u32(allData, 0x2cc)
	newData.maxSpeedFraction = get_s32(allData, 0x2a0)
	newData.snqcr = get_s32(allData, 0x3a8)
	--newData.ffms = get_s32(allData, 0xd4)
	--newData.slipstream = get_s32(allData, 0xd8)
	--newData.test = get_s32(allData, 0x1d4)
	--newData.scale = get_s32(allData, 0xc4)
	--newData.f230 = get_u32(allData, 0x230)

	-- Item
	local itemDataPtr = memory.read_s32_le(Memory.addrs.ptrItemInfo + 0x210 * allData[0x74])
	newData.roulleteItem = memory.read_u8(itemDataPtr + 0x2c)
	newData.itemId = memory.read_u8(itemDataPtr + 0x4c)
	newData.itemCount = memory.read_u8(itemDataPtr + 0x54)
	newData.roulleteTimer = memory.read_u8(itemDataPtr + 0x20)
	newData.roulleteState = memory.read_u8(itemDataPtr + 0x1C)
	
	return newData
end
local function getCheckpointData(dataObj)	
	if ptrCheckNum == 0 then
		return
	end
	
	-- Read checkpoint values
	dataObj.checkpoint = memory.read_u8(ptrCheckNum + 0x46)
	dataObj.keyCheckpoint = memory.read_s8(ptrCheckNum + 0x48)
	dataObj.checkpointGhost = memory.read_s8(ptrCheckNum + 0xD2)
	dataObj.keyCheckpointGhost = memory.read_s8(ptrCheckNum + 0xD4)
	dataObj.lap = memory.read_s8(ptrCheckNum + 0x38)
	
	-- Lap time
	dataObj.lap_f = memory.read_s32_le(ptrCheckNum + 0x18) * 1.0 / 60 - 0.05
	if (dataObj.lap_f < 0) then dataObj.lap_f = 0 end
end

local function setGhostInputs(form)
	local ptr = memory.read_s32_le(Memory.addrs.ptrGhostInputs)
	if ptr == 0 then error("How are you here?") end
	
	local currentInputs = memory.read_bytes_as_array(ptr, 0xdce)
	memory.write_bytes_as_array(ptr, form.ghostInputs)
	memory.write_s32_le(ptr, 1765) -- max input count for ghost
	-- lap times
	ptr = memory.read_s32_le(Memory.addrs.ptrSomeRaceData)
	memory.write_bytes_as_array(ptr + 0x3ec, form.ghostLapTimes)
	
	-- This frame's state won't have it, but any future state will.
	form.firstStateWithGhost = frame + 1
	
	-- Find the first frame where inputs differ.
	local frames = 0
	-- 5, not 4: Lua table is 1-based
	for i = 5, #currentInputs, 2 do
		if form.ghostInputs[i] ~= currentInputs[i] then
			break
		elseif form.ghostInputs[i + 1] ~= currentInputs[i + 1] then
			frames = frames + math.min(form.ghostInputs[i + 1], currentInputs[i + 1])
			break
		else
			frames = frames + currentInputs[i + 1]
			if currentInputs[i + 1] == 0 then
				return -- All ghost inputs match!
			end
		end
	end
	-- Rewind, clear state history
	local targetFrame = frames + form.firstGhostInputFrame
	-- I'm not sure why, but ghosts have been desyncing. So let's just go back a little more.
	targetFrame = targetFrame - 1
	if frame > targetFrame then
		local inputs = movie.getinput(targetFrame)
		local isOn = inputs["A"]
		tastudio.submitinputchange(targetFrame, "A", not isOn)
		tastudio.applyinputchanges()
		tastudio.submitinputchange(targetFrame, "A", isOn)
		tastudio.applyinputchanges()
	end
end
local function ensureGhostInputs(form)
	-- This function's job is to re-apply the hacked ghost data when the user re-winds far enough back that the hacked ghost isn't in the savestate.

	-- Ensure we're still in the same race
	local firstInputFrame = frame - memory.read_s32_le(memory.read_s32_le(Memory.addrs.ptrRaceTimers) + 4) + 121
	if firstInputFrame ~= form.firstGhostInputFrame then
		return
	end

	-- We don't want to be constantly re-applying every frame advance.
	if frame < lastFrame or form.firstStateWithGhost > frame then
		-- At this point, we should be in a state where the ghost inputs
		-- are only different from what they should be AFTER the current
		-- frame. Because the initial setting of inputs (at user click or
		-- at branch load) will have invalidated all states where the
		-- inputs don't match up to the frame of the state.
		-- However, BizHawk has a bug: It will sometimes return from
		-- emu.frameadvance() BEFORE triggering the branch load handler.
		-- In that case, we'd update ghost inputs here first and then the
		-- branch load handler would have no way of knowing where to
		-- rewind to/invalidate states. The easiest fix for this is to just
		-- always check for incorrect ghost inputs.
		setGhostInputs(form)
	end
end

local function getCourseData()
	-- Read pointer values
	ptrRacerData = memory.read_s32_le(Memory.addrs.ptrRacerData)
	ptrCheckNum = memory.read_s32_le(Memory.addrs.ptrCheckNum)
	ptrRaceTimers = memory.read_s32_le(Memory.addrs.ptrRaceTimers)
	ptrMissionInfo = memory.read_s32_le(Memory.addrs.ptrMissionInfo)

	triangles = KCL.getCourseCollisionData().triangles
	Objects.loadCourseData()
	checkpoints = Checkpoints.getCheckpoints()

	allRacers = {}
end

local function inRace()
	-- Check if racer exists.
	local currentRacersPtr = memory.read_s32_le(Memory.addrs.ptrRacerData)
	if currentRacersPtr == 0 then
		clearDataOutsideRace()
		return false
	end
	
	-- Check if race has begun. (This static pointer points to junk on the main menu, which is why we checked racer data first.)
	local timer = memory.read_s32_le(memory.read_s32_le(Memory.addrs.ptrRaceTimers) + 8)
	if timer == 0 then
		clearDataOutsideRace()
		return false
	end
	local currentCourseId = memory.read_u8(Memory.addrs.ptrCurrentCourse)
	if currentCourseId ~= course.id or currentRacersPtr ~= course.racersPtr or frame - timer ~= course.frame then
		course.id = currentCourseId
		course.racersPtr = currentRacersPtr
		course.frame = frame - timer
		getCourseData()
	end
	
	return true
end

local function getInGameCameraData()
	local cameraPtr = memory.read_u32_le(Memory.addrs.ptrCamera)
	local camPos = read_pos(cameraPtr + 0x24)
	local camTargetPos = read_pos(cameraPtr + 0x18)
	local direction = Vector.subtract(camPos, camTargetPos)
	direction = Vector.normalize_float(direction)
	local cameraFoVV = memory.read_u16_le(cameraPtr + 0x60) * satr
	local camAspectRatio = memory.read_s32_le(cameraPtr + 0x6C) / 0x1000
	return {
		location = camPos,
		direction = direction,
		fovW = math.tan(cameraFoVV * camAspectRatio) * 0xec0, -- Idk why not 0x1000, but this gives better results. /shrug
		fovH = math.tan(cameraFoVV) * 0x1000,
	}
end

-- Main info function
local function _mkdsinfo_run_data(isSameFrame)
	myData = getRacerDetails(ptrRacerData + watchingId * 0x5a8, myData, isSameFrame)

	racerCount = memory.read_s32_le(Memory.addrs.racerCount)
	allRacers = {} -- needs new object so drawPackages can have multiple frames
	for i = 0, racerCount - 1 do
		if i ~= watchingId then
			allRacers[i] = getRacerBasicData(ptrRacerData + i * 0x5a8, allRacers[i])
		else
			allRacers[i] = myData
		end
	end
	
	if watchingId == 0 then
		getCheckpointData(myData) -- This function only supports player.

		local ghostExists = racerCount >= 2 and Objects.isGhost(ptrRacerData + 0x5a8)
		if ghostExists then
			myData.ghost = allRacers[1]
			myData.ghost.pos = read_pos(myData.ghost.ptr + 0x80)
		else
			myData.ghost = nil
		end
	else
		myData.ghost = nil
	end

	if config.enableCameraFocusHack then
		local raceThing = memory.read_u32_le(Memory.addrs.ptrSomeRaceData)
		memory.write_u8(raceThing + 0x62, watchingId)
		memory.write_u8(raceThing + 0x63, watchingId)
		local somethingPtr = memory.read_u32_le(Memory.addrs.ptrCheckNum)
		memory.write_u32_le(somethingPtr + 0x4f0, 0)
		-- Visibility
		local racer = ptrRacerData + 0x5a8 * watchingId
		local ptr = memory.read_u32_le(racer + 0x590)
		memory.write_u8(ptr + 0x58, 0)
		memory.write_u8(ptr + 0x5c, 0)
		local shadowPtr = memory.read_u32_le(ptr + 0x1C)
		memory.write_u8(shadowPtr + 0x70, 1)
		local flags4e = memory.read_u8(racer + 0x4e)
		memory.write_u8(racer + 0x4e, flags4e & 0x7f)
		-- Wheels: Only way I know how is code hack.
		local value = 0
		if watchingId == 0 then value = 1 end
		memory.write_u8(Memory.addrs.cameraThing, value)
	end

	local o = Objects.getNearbyObjects(myData, config.objectRenderDistance)
	nearbyObjects = o[1]
	myData.nearestObject = o[2]

	-- Ghost handling
	if form.ghostInputs ~= nil then
		ensureGhostInputs(form)
	end
	lastFrame = frame
	
	if config.giveGhostShrooms then
		local itemPtr = memory.read_s32_le(Memory.addrs.ptrItemInfo)
		itemPtr = itemPtr + 0x210 -- ghost
		memory.write_u8(itemPtr + 0x4c, 5) -- mushroom
		memory.write_u8(itemPtr + 0x54, 3) -- count
	end

	-- Data not tied to a racer
	raceData.framesMod8 = memory.read_s32_le(ptrRaceTimers + 0xC)
	raceData.coinsBeingCollected = memory.read_s16_le(ptrMissionInfo + 0x8)

	local drawingPackage = {
		allRacers = allRacers,
		allTriangles = triangles,
		objects = nearbyObjects,
		checkpoints = checkpoints,
	}
	if not isSameFrame then
		drawingPackages[3] = drawingPackages[2]
		drawingPackages[2] = drawingPackages[1]
		drawingPackages[1] = drawingPackage
		gameCameraHisotry[1] = gameCameraHisotry[2]
		gameCameraHisotry[2] = gameCameraHisotry[3]
		gameCameraHisotry[3] = getInGameCameraData()
	end
end
---------------------------------------

-- Drawing --------------------------------------
local iView = {}

local function drawText(x, y, str, color)
	gui.text(x + iView.x, y + iView.y, str, color)
end

local function drawInfoBottomScreen(data)
	gui.use_surface("client")
	
	local lineHeight = 15 -- there's no font size option!?
	local sectionMargin = 8
	local y = 4
	local x = 4
	local b = true
	local function dt(s)
		if s == nil then
			print("drawing nil at y " .. y)
		end
		gui.text(x + iView.x, y + iView.y, s)
		y = y + lineHeight
		b = false
	end
	local sectionIsDark = false
	local lastSectionBegin = 0
	local function endSection()
		if b then return end
		b = true
		y = y + sectionMargin / 2 + 1
		if sectionIsDark then
			gui.drawBox(iView.x, lastSectionBegin + iView.y, iView.x + iView.w, y + iView.y, 0xff000000, 0xff000000)
		else
			gui.drawBox(iView.x, lastSectionBegin + iView.y, iView.x + iView.w, y + iView.y, 0x60000000, 0x60000000)
		end
		gui.drawLine(iView.x, y + iView.y, iView.x + iView.w, y + iView.y, "red")
		sectionIsDark = not sectionIsDark
		lastSectionBegin = y + 1
		y = y + sectionMargin / 2 - 1
	end

	local f = string.format
	
	-- Display speed, boost stuff
	dt(f("Boost: %2i, MT: %2i, %i", data.boostAll, data.boostMt, data.mtTime))
	dt(f("Speed: %i, real: %.1f", data.speed, data.real2dSpeed))
	dt(f("Y Sp : %i, Max Sp: %i", data.verticalVelocity, data.maxSpeed))
	local wallClip = data.wallSpeedMult
	local losses = "turnLoss: " .. format01(data.turnLoss)
	if wallClip ~= 4096 or data.flags44 & 0xc0 ~= 0 then
		losses = losses .. ", wall: " .. format01(data.wallSpeedMult)
	end
	if data.airSpeed ~= 4096 then
		losses = losses .. ", air: " .. format01(data.airSpeed)
	end
	if data.effectSpeed ~= 4096 then
		losses = losses .. ", small: " .. format01(data.effectSpeed)
	end
	dt(losses)
	endSection()

	-- Display position
	dt(data.air .. " (" .. data.framesInAir .. ")")
	dt(posVecToStr(data.pos, "X, Z, Y  : "))
	dt(posVecToStr(data.actualPosDelta, "Delta    : "))
	local bm = Vector.add(Vector.subtract(data.pos, data.actualPosDelta), data.basePosDelta)
	local pod = Vector.subtract(data.posForObjects, bm)
	dt(posVecToStr(data.collisionPush, "Collision: "))
	dt(posVecToStr(pod, "Hitbox   : "))
	endSection()
	-- Display angles
	if config.showAnglesAsDegrees then
		-- People like this
		local function atd(a)
			return (((a / 0x10000) * 360) + 360) % 360
		end
		local function ttd(v)
			local radians = math.atan(v[1], v[3])
			return radians * 360 / (2 * math.pi)
		end
		dt(f("Facing angle: %.3f", atd(data.facingAngle)))
		local da = atd(data.driftAngle)
		if da > 180 then da = da - 360 end
		dt(f("Drift angle: %.3f",  da))
		dt(f("Movement angle: %.3f (%.3f)", ttd(data.movementDirection), ttd(data.movementTarget)))
	else
		-- Suuper likes this
		dt(f("Angle: %6i + %6i = %6i", data.facingAngle, data.driftAngle, data.facingAngle + data.driftAngle))
		dt(f("Delta: %6i + %6i = %6i", data.facingDelta, data.driftDelta, data.facingDelta + data.driftDelta))
		local function tta(v)
			local radians = math.atan(v[1], v[3])
			local dsUnits = math.floor(radians * 0x10000 / (2 * math.pi))
			return f(" (%5.3f, %6i)", Vector.get2dMagnitude(v), dsUnits)
		end
		dt(normalVectorToStr(data.movementDirection, "Movement: ") .. tta(data.movementDirection))
		dt(normalVectorToStr(data.movementTarget, "Target  : ") .. tta(data.movementTarget))
	end
	dt(f("Pitch: %i (%i, %i)", data.pitch, quaternionAngle(data.snQuaternion), quaternionAngle(data.snqTarget)))
	endSection()
	-- surface stuff
	local n = data.surfaceNormalVector
	if config.showExactMovement then
		dt(f("Surface grip: %4i, sp: %4i,", data.grip, data.offroadSpeed))
	else
		dt(f("Surface grip: %6.3f, sp: %6.3f,", data.grip, data.offroadSpeed))
	end
	local steepness = Vector.get2dMagnitude(n) / (n[2] / 0x1000)
	steepness = f(", steep: %#.2f", steepness)
	dt(normalVectorToStr(n, "normal: ") .. steepness)
	endSection()
	
	-- Wall assist
	dt(rawQuaternion(data.snQuaternion, "Real:   "))
	dt(rawQuaternion(data.snqTarget,    "Target: "))

	-- Ghost comparison
	if data.ghost then
		local distX = data.pos[1] - data.ghost.pos[1]
		local distZ = data.pos[3] - data.ghost.pos[3]
		local dist = math.sqrt(distX * distX + distZ * distZ)
		dt(f("Distance from ghost (2D): %.0f", dist))
		endSection()
	end
	
	-- Point comparison
	if form.comparisonPoint ~= nil then
		local delta = {
			data.pos[1] - form.comparisonPoint[1],
			data.pos[3] - form.comparisonPoint[3]
		}
		local dist = math.floor(math.sqrt(delta[1] * delta[1] + delta[2] * delta[2]))
		local angleRad = math.atan(delta[1], delta[2])
		dt("Distance travelled: " .. dist)
		dt("Angle: " .. math.floor(angleRad * 0x10000 / (2 * math.pi)))
		endSection()
	end

	-- Nearest object
	if data.nearestObject ~= nil then
		local obj = data.nearestObject
		dt(f("Object distance: %.0f (%s, %s)", obj.distance, obj.hitboxType, obj.type))
		if obj.distanceComponents ~= nil then
			if obj.innerDistComps ~= nil then
				dt(posVecToStr(obj.distanceComponents, "outer: "))
				dt(posVecToStr(obj.innerDistComps, "inner: "))
			elseif obj.distanceComponents.v == nil then
				dt(posVecToStr(obj.distanceComponents))
			else
				dt(string.format("%9i, %8i", obj.distanceComponents.h, obj.distanceComponents.v))
			end
		end
		endSection()
	end
	
	-- bouncy stuff
	if Vector.getMagnitude(data.movementAdd1fc) ~= 0 then
		dt(normalVectorToStr(data.movementAdd1fc, "bounce 1: "))
	end
	if Vector.getMagnitude(data.movementAdd2f0) ~= 0 then
		dt(normalVectorToStr(data.movementAdd2f0, "bounce 2: "))
	end
	if Vector.getMagnitude(data.movementAdd374) ~= 0 then
		dt(normalVectorToStr(data.movementAdd374, "bounce 3: "))
	end
	if data.waterfallStrength ~= 0 then
		dt(normalVectorToStr(Vector.multiply_r(data.waterfallPush, data.waterfallStrength), "waterfall: "))
	end
	endSection()
	
	-- tmep?
	--dt(rawQuaternion(data.snQuaternion, "snq: "))
	--dt(rawQuaternion(data.snqTarget, "trg: "))
	--dt(data.maxSpeedFraction)
	--dt(data.snqcr)
	--dt("4de: " .. data.f4de)
	--dt("smsm: " .. data.smsm)
	--dt(data.radius)
	
	-- Display checkpoints
	if data.checkpoint ~= nil then
		if (data.spawnPoint > -1) then dt("Spawn Point: " .. data.spawnPoint) end
		dt(f("Checkpoint number (player) = %i (%i)", data.checkpoint, data.keyCheckpoint))
		dt("Lap: " .. data.lap)
		endSection()
	end
	
	-- Coins
	if raceData.coinsBeingCollected ~= nil and raceData.coinsBeingCollected > 0 then
		local coinCheckIn = nil
		if raceData.framesMod8 == 0 then
			dt("Coin increment this frame")
		else
			dt(f("Coin increment in %i frames", 8 - raceData.framesMod8))
		end
		endSection()
	end
	
	--y = 37
	--x = 350
	-- Display lap time
	--if data.lap_f then
	--	dt("Lap: " .. time(data.lap_f))
	--end
end
local itemNames = {
	"red shell", "banana", "fake item box",
	"mushroom", "triple mushroom", "bomb",
	"blue shell", "lightning", "triple greens",
	"triple banana", "triple reds", "star",
	"gold mushroom", "bullet bill", "blooper",
	"boo", "invalid17", "invalid18",
	"none",
}
itemNames[0] = "green shell"
local function drawItemInfo(data)
	if data.roulleteItem ~= 19 then
		gui.text(6, 84, itemNames[data.roulleteItem])
		if data.roulleteState == 1 then
			local ttpi = 60 - data.roulleteTimer
			if ttpi <= 0 then
				gui.text(6, 100, "stop roullete now")
			else
				gui.text(6, 100, string.format("stop in %i frames", ttpi))
			end
		elseif data.roulleteState == 2 then
			local ttpi = 33 - data.roulleteTimer
			gui.text(6, 100, string.format("use in %i frames", ttpi))
		end
	end
end

-- Collision drawing ----------------------------
local mainCamera = {
	orthographic = true,
	scale = config.defaultScale,
	perspectiveId = -5,
	overlay = false,
	drawKcl = true,
	drawObjects = true,
	drawCheckpoints = false,
	racerId = 0,
	drawText = function(x, y, s, c) gui.text(x + iView.x, iView.y - y, s, c) end,
	isPrimary = true,
	useDelay = true,
	active = false,
	renderAllTriangles = config.renderAllTriangles,
}
local viewports = {}

local originalPadding = nil

local function updateDrawingRegions(camera)
	local clientWidth = client.screenwidth()
	local clientHeight = client.screenheight()
	local layout = nds.getscreenlayout()
	local gap = nds.getscreengap()
	--local invert = nds.getscreeninvert()
	local gameBaseWidth = nil
	local gameBaseHeight = nil
	if layout == "Natural" then
		-- We do not support rotated screens. Assume vertical.
		layout = "Vertical"
	end
	if layout == "Vertical" then
		gameBaseWidth = 256
		gameBaseHeight = 192 * 2 + gap
	elseif layout == "Horizontal" then
		gameBaseWidth = 256 * 2
		gameBaseHeight = 192
	else
		gameBaseWidth = 256
		gameBaseHeight = 192
	end
	local gameScale = math.min(clientWidth / gameBaseWidth, clientHeight / gameBaseHeight)
	local colView = {
		w = 0.5 * 256 * gameScale,
		h = 0.5 * 192 * gameScale,
	}
	colView.x = (clientWidth - gameBaseWidth * gameScale) * 0.5 + colView.w
	colView.y = (clientHeight - gameBaseHeight * gameScale) * 0.5 + colView.h
	iView = {
		x = (clientWidth - (gameBaseWidth * gameScale)) * 0.5,
		y = (clientHeight - (gameBaseHeight * gameScale)) * 0.5,
		w = 256 * gameScale,
		h = 192 * gameScale,
	}
	if layout ~= "Horizontal" then
		-- People who use wide window (black space to the side of game screen) tell me they prefer info to be displayed on the left rather than over the bottom screen.
		iView.x = 0
		iView.y = iView.y + (192 + gap) * gameScale
		if config.drawOnLeftSide == true then
			if mainCamera.overlay == false then
				colView.x = colView.w
			end
		end
	else
		iView.x = iView.x + 256 * gameScale
	end

	camera.x = colView.x
	camera.y = colView.y
	camera.w = colView.w
	camera.h = colView.h
end
updateDrawingRegions(mainCamera)

Graphics.setPerspective(mainCamera, { 0, 0x1000, 0 })

local function updateViewport(viewport)
	if viewport == mainCamera then
		-- Camera view overrides other viewpoint settings
		if mainCamera.overlay == true then
			local ch = gameCameraHisotry[1]
			if ch.location == nil then ch = gameCameraHisotry[3] end
			mainCamera.location = ch.location
			mainCamera.fovW = ch.fovW
			mainCamera.fovH = ch.fovH
			Graphics.setPerspective(mainCamera, ch.direction)
			mainCamera.orthographic = false
		elseif mainCamera.frozen == true then
			mainCamera.location = mainCamera.freezePoint
		else
			mainCamera.location = allRacers[viewport.racerId].posForObjects
		end
	elseif viewport.frozen ~= true then	
		if viewport.perspectiveId == -6 then
			local ch = gameCameraHisotry[3]
			viewport.location = ch.location
			viewport.fovW = ch.fovW
			viewport.fovH = ch.fovH
			Graphics.setPerspective(viewport, ch.direction)
		else
			viewport.location = allRacers[viewport.racerId].posForObjects
		end
	end
end
local function drawViewport(viewport)
	if viewport == mainCamera then
		local id = 1
		if (not mainCamera.orthographic) and (mainCamera.useDelay and mainCamera.active) then
			id = 3
			if drawingPackages[id] == nil then
				id = 2
				if drawingPackages[id] == nil then id = 1 end
			end
		end
		if drawingPackages[id] == nil then error("nil package") end

		gui.use_surface("client")
		Graphics.drawClient(mainCamera, drawingPackages[id])
	else
		Graphics.drawForms(viewport, drawingPackages[1])
	end
end

-- Main drawing function
local function _mkdsinfo_run_draw(isInRace)
	-- BizHawk is slow. Let's tell it to not worry about waiting for this.
	if not client.ispaused() and not drawWhileUnpaused then
		if client.isseeking() then
			-- We need special logic here. BizHawk will not set paused = true at end of seek before this script runs!
			emu.yield()
			if not client.ispaused() then
				return
			end
		else
			-- I would just yield, then check if we're still on the same frame and draw then.
			-- However, BizHawk will not display anything we draw after a yield, while not paused.
			return
		end
	end
	
	gui.clearGraphics("client")
	gui.clearGraphics("emucore")
	gui.cleartext()
	if isInRace then
		if config.showBottomScreenInfo then
			drawInfoBottomScreen(myData)
			drawItemInfo(myData)
		end

		updateViewport(mainCamera)
		drawViewport(mainCamera)
		for i = 1, #viewports do
			updateViewport(viewports[i])
			drawViewport(viewports[i])
		end
	else
		drawText(10, 10, "Not in a race.")
	end
end
-------------------------------------------------

-- UI --------------------------------
local function redraw(farRewind)
	-- BizHawk won't clear it for us on the next frame, if we don't actually draw anything on the next frame.
	gui.clearGraphics("client")
	gui.clearGraphics("emucore")
	gui.cleartext()

	-- If we are not paused, there's no point in redrawing. The next frame will be here soon enough.
	if not client.ispaused() then
		return
	end
	-- BizHawk does not let us re-draw while paused. So the only way to redraw is to rewind and come back to this frame.
	-- Update: BizHawk 2.10 does let us re-draw!
	if bizhawkVersion < 10 and not tastudio.engaged() then
		return
	elseif bizhawkVersion >= 10 and not farRewind then
		if inRace() then
			_mkdsinfo_run_data(true)
			_mkdsinfo_run_draw(true)
		else
			_mkdsinfo_run_draw(false)
		end
		return
	else
		print(bizhawkVersion, farRewind)
	end

	-- emu.yield() -- this throws an Exception in BizHawk's code
	-- We ALSO cannot use tastudio.setplayback for the frame we want. Because BizHawk freezes the UI and won't run Lua while such a seek is happening so 
	-- (1) we won't have the right data when it's done and (2) we have no way of knowing when it is done.
	-- So we must actually tell TAStudio to rewind to 3 frames earlier.
	-- Then we can have Lua run over the next two frames, collecting data for the frame we want and the frames prior (for camera data + position delta).
	-- But we also must tell TAStudio to seek to a frame that is preceeded by a state; else it will rewind+emulate with a non-responsive UI.
	local f = frame - 3
	if farRewind then f = f - 3 end
	while not tastudio.hasstate(f - 1) and f >= 0 do
		f = f - 1
	end
	tastudio.setplayback(f)
	redrawSeek = frame
	client.unpause()
end

local function useInputsClick()
	if not inRace() then
		print("You aren't in a race.")
		return
	end
	if not tastudio.engaged() then
		return
	end
	
	if form.ghostInputs == nil then
		form.ghostInputs = memory.read_bytes_as_array(memory.read_s32_le(Memory.addrs.ptrPlayerInputs), 0xdce) -- 0x8ace)
		form.firstGhostInputFrame = frame - memory.read_s32_le(memory.read_s32_le(Memory.addrs.ptrRaceTimers) + 4) + 121
		form.ghostLapTimes = memory.read_bytes_as_array(memory.read_s32_le(Memory.addrs.ptrCheckNum) + 0x20, 0x4 * 5)
		setGhostInputs(form)
		forms.settext(form.ghostInputHackButton, "input hack active")
	else
		form.ghostInputs = nil
		forms.settext(form.ghostInputHackButton, "Copy from player")
	end
end
local function _watchUpdate()
	local s = "player"
	if watchingId ~= 0 then
		if Objects.isGhost(allRacers[watchingId].ptr) then
			s = "ghost"
		else
			s = "cpu " .. watchingId
		end
	end
	forms.settext(form.watchLabel, s)

	redraw(config.enableCameraFocusHack) -- Will rewind and so grab data for newly watched racer.
end
local function watchLeftClick()
	watchingId = watchingId - 1
	if watchingId == -1 then
		watchingId = memory.read_s32_le(Memory.addrs.racerCount) - 1
	end
	_watchUpdate()
end
local function watchRightClick()
	watchingId = watchingId + 1
	if watchingId >= memory.read_s32_le(Memory.addrs.racerCount) then
		watchingId = 0
	end
	_watchUpdate()
end

local function setComparisonPointClick()
	if form.comparisonPoint == nil then
		local pos = myData.pos
		form.comparisonPoint = { pos[1], pos[2], pos[3] }
		forms.settext(form.setComparisonPoint, "Clear comparison point")
	else
		form.comparisonPoint = nil
		forms.settext(form.setComparisonPoint, "Set comparison point")
	end
end
local function loadGhostClick()
	local fileName = forms.openfile(nil,nil,"TAStudio Macros (*.bk2m)|*.bk2m|All Files (*.*)|*.*")
	local inputFile = assert(io.open(fileName, "rb"))
	local inputHeader = inputFile:read("*line")
	-- Parse the header
	local names = {}
	local index = 0
	local nextIndex = string.find(inputHeader, "|", index)
	while nextIndex ~= nil do
		names[#names + 1] = string.sub(inputHeader, index, nextIndex - 1)
		index = nextIndex + 1
		nextIndex = string.find(inputHeader, "|", index)
		if #names > 100 then
			error("unable to parse header")
		end
	end
	nextIndex = string.len(inputHeader)
	names[#names + 1] = string.sub(inputHeader, index, nextIndex - 1)
	-- ignore next 3 lines
	local line = inputFile:read("*line")
	while string.sub(line, 1, 1) ~= "|" do
		line = inputFile:read("*line")
	end
	-- parse inputs
	local inputs = {}
	while line ~= nil and string.sub(line, 1, 1) == "|" do
		-- |  128,   96,    0,    0,.......A...r....|
		-- Assuming all non-button inputs are first.
		local id = 1
		index = 0
		local nextComma = string.find(line, ",", index)
		while nextComma ~= nil do
			id = id + 1
			index = nextComma + 1
			nextComma = string.find(line, ",", index)
			if id > 100 then
				error("unable to parse input")
			end
		end
		-- now buttons
		local buttons = 0
		while id <= #names do
			if string.sub(line, index, index) ~= "." then
				if names[id] == "A" then buttons = buttons | 0x01
				elseif names[id] == "B" then buttons = buttons | 0x02
				elseif names[id] == "R" then buttons = buttons | 0x04
				elseif names[id] == "X" or names[id] == "L" then buttons = buttons | 0x08
				elseif names[id] == "Right" then buttons = buttons | 0x10
				elseif names[id] == "Left" then buttons = buttons | 0x20
				elseif names[id] == "Up" then buttons = buttons | 0x40
				elseif names[id] == "Down" then buttons = buttons | 0x80
				end
			end
			id = id + 1
			index = index + 1
		end
		inputs[#inputs + 1] = buttons
		line = inputFile:read("*line")
	end
	inputFile:close()
	-- turn inputs into MKDS recording format (buttons, count)
	local bytes = { 0, 0, 0, 0 }
	local count = 1
	local lastInput = inputs[1]
	for i = 2, #inputs do
		if inputs[i] ~= lastInput or count == 255 then
			bytes[#bytes + 1] = lastInput
			bytes[#bytes + 1] = count
			lastInput = inputs[i]
			count = 1
			if #bytes == 0xdcc then
				print("Maximum ghost recording length reached.")
				break
			end
		else
			count = count + 1
		end
	end
	while #bytes < 0xdcc do bytes[#bytes + 1] = 0 end
	-- write
	form.ghostInputs = bytes
	form.firstGhostInputFrame = frame - memory.read_s32_le(memory.read_s32_le(Memory.addrs.ptrRaceTimers) + 4) + 121
	form.ghostLapTimes = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
	setGhostInputs(form)
	forms.settext(form.ghostInputHackButton, "input hack active")

end
local function saveCurrentInputsClick()
	-- BizHawk doesn't expose a file open function (Lua can still write to files, we just don't have a nice way to let the user choose a save location.)
	-- So instead, we just tell the user which frames to save.
	local firstInputFrame = frame - memory.read_s32_le(memory.read_s32_le(Memory.addrs.ptrRaceTimers) + 4) + 121
	print("BizHawk doesn't give Lua a save file dialog.")
	print("You can manually save your current inputs as a .bk2m:")
	print("1) Select frames " .. firstInputFrame .. " to " .. frame .. " (or however many frames you want to include).")
	print("2) File -> Save Selection to Macro")
end

local function branchLoadHandler(branchId)
	if shouldExit or form == nil then
		-- BizHawk bug: Registered events continue to run after a script has stopped.
		tastudio.onbranchload(function() end)
		return
	end
	if form.firstStateWithGhost ~= 0 then
		form.firstStateWithGhost = 0
	end
	if form.ghostInputs ~= nil and inRace() then
		-- Must call emu.framecount instead of using our frame variable, since we've just loaded a branch. And then potentially had TAStudio rewind.
		local currentFrame = emu.framecount()
		setGhostInputs(form)
		if emu.framecount() ~= currentFrame and config.alertOnRewindAfterBranch then
			print("Movie rewind: ghost inputs changed after branch load.")
			print("Stop ghost input hacker to load branch without rewind.")
		end
	end
end

local function drawUnpausedClick()
	drawWhileUnpaused = not drawWhileUnpaused
	if drawWhileUnpaused then
		forms.settext(form.drawUnpausedButton, "Draw while unpaused: ON")
	else
		forms.settext(form.drawUnpausedButton, "Draw while unpaused: OFF")
	end
end

local function kclClick()
	mainCamera.active = not mainCamera.active
	redraw()
end
local function zoomInClick(camera)
	camera = camera or mainCamera
	camera.scale = camera.scale * 0.8
	drawViewport(camera)
end
local function zoomOutClick(camera)
	camera = camera or mainCamera
	camera.scale = camera.scale / 0.8
	drawViewport(camera)
end

local function _changePerspective(cam)
	if cam == mainCamera then
		forms.setproperty(form.delayCheckbox, "Visible", false)
	end

	local id = cam.perspectiveId
	if id < 0 then
		local presets = {
			{ "camera", nil },
			{ "top down", { 0, 0x1000, 0 }},
			{ "north-south", { 0, 0, -0x1000 }},
			{ "south-north", { 0, 0, 0x1000 }},
			{ "east-west", { 0x1000, 0, 0 }},
			{ "west-east", { -0x1000, 0, 0 }},
		}
		if id == -6 then
			-- camera
			local cameraPtr = memory.read_u32_le(Memory.addrs.ptrCamera)
			local direction = read_pos(cameraPtr + 0x15c)
			Graphics.setPerspective(cam, Vector.multiply(direction, -1))
			cam.orthographic = false
			cam.overlay = cam == mainCamera
			if cam == mainCamera then
				forms.setproperty(form.delayCheckbox, "Visible", true)
			end
		else
			Graphics.setPerspective(cam, presets[id + 7][2])
			cam.orthographic = true
			cam.overlay = false
		end
		forms.settext(cam.perspectiveLabel, presets[id + 7][1])
	else
		if triangles == nil or triangles[id] == nil then error("no such triangle") end
		Graphics.setPerspective(cam, triangles[id].surfaceNormal)
		cam.orthographic = true
		cam.overlay = false
		forms.settext(cam.perspectiveLabel, "triangle " .. id)
	end

	if cam.box == nil then
		redraw()
	elseif cam.frozen ~= true then
		if cam.perspectiveId == -6 then
			local camData = getInGameCameraData()
			cam.location = camData.location
			cam.fovW = camData.fovW
			cam.fovH = camData.fovH
			Graphics.setPerspective(cam, camData.direction)
		else
			cam.location = myData.posForObjects
		end
		redraw()
	end
end
local function changePerspectiveLeft(cam)
	cam = cam or mainCamera

	local id = cam.perspectiveId
	id = id - 1
	if id < -6 then
		id = 9999
	end
	if id >= 0 then
		-- find next nearby triangle ID
		local racer = allRacers[cam.racerId]
		local tris = KCL.getNearbyTriangles(racer.posForObjects)
		local nextId = 0
		for i = 1, #tris do
			local ti = tris[i].id
			if ti < id and ti > nextId then
				if not Vector.equals(cam.rotationVector, tris[i].surfaceNormal) then
					nextId = ti
				end
			end
		end
		if nextId == 0 then
			id = -1
		else
			id = nextId
		end
	end
	cam.perspectiveId = id
	_changePerspective(cam)
end
local function changePerspectiveRight(cam)
	cam = cam or mainCamera

	local id = cam.perspectiveId
	id = id + 1
	if id >= 0 then
		-- find next nearby triangle ID
		local racer = allRacers[cam.racerId]
		local tris = KCL.getNearbyTriangles(racer.posForObjects)
		local nextId = 9999
		for i = 1, #tris do
			local ti = tris[i].id
			if ti >= id and ti < nextId then
				if not Vector.equals(cam.rotationVector, tris[i].surfaceNormal) then
					nextId = ti
				end
			end
		end
		if nextId == 9999 then
			id = -6
		else
			id = nextId
		end
	end
	cam.perspectiveId = id
	_changePerspective(cam)
end

local function makeCollisionControls(kclForm, viewport, x, y)
	local labelMargin = 2
	local baseY = y

	-- where is the camera+focus
	local temp = forms.label(kclForm, "Zoom", x, y + 4)
	forms.setproperty(temp, "AutoSize", true)
	temp = forms.button(
		kclForm, "+", function() zoomInClick(viewport) end,
		forms.getproperty(temp, "Right") + labelMargin, y,
		23, 23
	)
	temp = forms.button(
		kclForm, "-", function() zoomOutClick(viewport) end,
		forms.getproperty(temp, "Right") + labelMargin, y,
		23, 23
	)
	y = y + 26
	temp = forms.label(
		kclForm, "Perspective:",
		x, y + 4
	)
	forms.setproperty(temp, "AutoSize", true)
	temp = forms.button(
		kclForm, "<", function() changePerspectiveLeft(viewport) end,
		forms.getproperty(temp, "Right") + labelMargin*2, y,
		18, 23
	)
	viewport.perspectiveLabel = forms.label(
		kclForm, "top down",
		forms.getproperty(temp, "Right") + labelMargin*2, y + 4
	)
	forms.setproperty(viewport.perspectiveLabel, "AutoSize", true)
	temp = forms.button(
		kclForm, ">", function() changePerspectiveRight(viewport) end,
		forms.getproperty(viewport.perspectiveLabel, "Right") + 22, y,
		18, 23
	)
	local rightmost = forms.getproperty(temp, "Right") + 0
	y = y + 26
	temp = forms.checkbox(kclForm, "freeze location", x + 1, y)
	forms.setproperty(temp, "AutoSize", true)
	forms.addclick(temp, function()
		viewport.frozen = not viewport.frozen
		viewport.freezePoint = viewport.location
		if not viewport.frozen then
			redraw()
		end
	end)

	-- what is drawn
	y = baseY
	x = rightmost - 10
	temp = forms.label(kclForm, "Draw:", x, y + 3)
	forms.setproperty(temp, "AutoSize", true)
	x = forms.getproperty(temp, "Right") + labelMargin
	temp = forms.checkbox(kclForm, "kcl", x, y + 3)
	forms.setproperty(temp, "AutoSize", true)
	forms.setproperty(temp, "Checked", true)
	forms.addclick(temp, function() viewport.drawKcl = not viewport.drawKcl; redraw(); end)
	y = y + 26
	temp = forms.checkbox(kclForm, "objects", x, y + 3)
	forms.setproperty(temp, "AutoSize", true)
	forms.setproperty(temp, "Checked", true)
	forms.addclick(temp, function() viewport.drawObjects = not viewport.drawObjects; redraw(); end)
	y = y + 26
	temp = forms.checkbox(kclForm, "checkpoints", x, y + 3)
	forms.setproperty(temp, "AutoSize", true)
	forms.addclick(temp, function() viewport.drawCheckpoints = not viewport.drawCheckpoints; redraw(); end)
end

local function makeNewKclView()
	local viewport = {
		orthographic = true,
		scale = config.defaultScale,
		w = 200,
		h = 150,
		x = 200,
		y = 150,
		perspectiveId = -5, -- top down
		overlay = false,
		drawCheckpoints = false,
		racerId = 0,
		drawKcl = true,
		drawObjects = true,
		active = true,
		renderAllTriangles = config.renderAllTriangles,
	}
	Graphics.setPerspective(viewport, {0, 0x1000, 0})

	viewport.window = forms.newform(viewport.w * 2, viewport.h * 2 + 76, "KCL View", function ()
		MKDS_INFO_FORM_HANDLES[viewport.window] = nil
		removeItem(viewports, viewport)
	end)
	MKDS_INFO_FORM_HANDLES[viewport.window] = true
	local theBox = forms.pictureBox(viewport.window, 0, 76, viewport.w * 2, viewport.h * 2)
	viewport.box = theBox
	forms.setproperty(viewport.window, "FormBorderStyle", "Sizable")
	-- No resize events. Make a resize/refresh button? Click the box? Box is easy but would be a kinda hidden feature.
	local temp = forms.label(viewport.window, "Click the box to resize it!", 15, viewport.h * 2 + 80)
	forms.setproperty(temp, "AutoSize", true)

	viewport.boxWidthDelta = forms.getproperty(viewport.window, "Width") - forms.getproperty(theBox, "Width")
	viewport.boxHeightDelta = forms.getproperty(viewport.window, "Height") - forms.getproperty(theBox, "Height")
	forms.addclick(theBox, function()
		local width = forms.getproperty(theBox, "Width")
		local height = forms.getproperty(theBox, "Height")
		-- Is this a resize?
		local fw = forms.getproperty(viewport.window, "Width")
		local fh = forms.getproperty(viewport.window, "Height")
		if fw - width ~= viewport.boxWidthDelta or fh - height ~= viewport.boxHeightDelta then
			forms.setsize(theBox, fw - viewport.boxWidthDelta, fh - viewport.boxHeightDelta)
			viewport.w = (fw - viewport.boxWidthDelta) / 2
			viewport.h = (fh - viewport.boxHeightDelta) / 2
			viewport.x = viewport.w
			viewport.y = viewport.h
			redraw()
			return
		end

		width = width / 2
		height = height / 2
		local x = viewport.scale * (forms.getMouseX(theBox) - width)
		local y = viewport.scale * (forms.getMouseY(theBox) - height)
		y = -y
		-- Solve the system of linear equations to find which 3D directions to move in
		local directions = Graphics.getDirectionsFrom2d(viewport)
		viewport.location = Vector.add(viewport.location, Vector.multiply(directions[1], x))
		viewport.location = Vector.add(viewport.location, Vector.multiply(directions[2], y))
		local wasFrozen = viewport.frozen
		viewport.frozen = true
		redraw()
		viewport.frozen = wasFrozen
	end)

	--gui.drawString(5, i * 15, "asdf this is a text test string drawing", nil, nil, 16, "courier new", "bold")
	forms.setDefaultTextBackground(theBox, 0xff222222)
	viewport.drawText = function(x, y, t, c) forms.drawText(theBox, x, viewport.h + viewport.h - y, t, c, nil, 14, "verdana", "bold") end

	makeCollisionControls(viewport.window, viewport, 5, 3)

	viewports[#viewports + 1] = viewport
	updateViewport(viewport)
	drawViewport(viewport)
end

local bizHawkEventIds = {}
if MKDS_INFO_FORM_HANDLES == nil then MKDS_INFO_FORM_HANDLES = {} end
local function _mkdsinfo_close()
	if config.drawOnLeftSide == true and originalPadding ~= nil then
		client.SetClientExtraPadding(originalPadding.left, originalPadding.top, originalPadding.right, originalPadding.bottom)
	end
	for k, _ in pairs(MKDS_INFO_FORM_HANDLES) do
		forms.destroy(k)
	end
	MKDS_INFO_FORM_HANDLES = {}
	
	for i = 1, #bizHawkEventIds do
		event.unregisterbyid(bizHawkEventIds[i])
	end
	
	-- Undo camera hack
	if watchingId ~= 0 and inRace() then
		local raceThing = memory.read_u32_le(Memory.addrs.ptrSomeRaceData)
		memory.write_u8(raceThing + 0x62, 0)
		memory.write_u8(raceThing + 0x63, 0)
	end

	gui.clearGraphics("client")
	gui.clearGraphics("emucore")
	gui.cleartext()
	hasClosed = true
end
local function _mkdsinfo_setup()
	if emu.framecount() < 400 then
		-- <400: rough detection of if stuff we need is loaded
		-- Specifically, we find addresses of hitbox functions.
		print("Looks like some data might not be loaded yet. Re-start this Lua script at a later frame.")
		shouldExit = true
		return
	elseif config.showBizHawkDumbnessWarning then
		print("BizHawk's Lua API is horrible. In order to work around bugs and other limitations, do not stop this script through BizHawk. Instead, close the window it creates and it will stop itself.")
	end

	for k, _ in pairs(MKDS_INFO_FORM_HANDLES) do
		forms.destroy(k)
	end
	MKDS_INFO_FORM_HANDLES = {}
	
	form = {}
	form.firstStateWithGhost = 0
	form.comparisonPoint = nil
	form.handle = forms.newform(305, 220, "MKDS Info Thingy", function()
		MKDS_INFO_FORM_HANDLES[form.handle] = nil
		if my_script_id == script_id then
			shouldExit = true
			if bizhawkVersion == 9 then
				redraw()
			else
				_mkdsinfo_close()
			end
		end
	end)
	MKDS_INFO_FORM_HANDLES[form.handle] = true
	
	local buttonMargin = 5
	local labelMargin = 2
	local y = 10

	local temp = forms.label(form.handle, "Watching: ", 10, y + 4)
	forms.setproperty(temp, "AutoSize", true)
	form.watchLeft = forms.button(
		form.handle, "<", watchLeftClick,
		forms.getproperty(temp, "Right") + labelMargin, y,
		18, 23
	)
	form.watchLabel = forms.label(form.handle, "player", forms.getproperty(form.watchLeft, "Right") + labelMargin, y + 4)
	forms.setproperty(form.watchLabel, "AutoSize", true)
	form.watchRight = forms.button(
		form.handle, ">", watchRightClick,
		forms.getproperty(form.watchLabel, "Right") + labelMargin, y,
		18, 23
	)
	
	form.setComparisonPoint = forms.button(
		form.handle, "Set comparison point", setComparisonPointClick,
		forms.getproperty(form.watchRight, "Right") + buttonMargin, y,
		100, 23
	)
	
	y = y + 28
	temp = forms.label(form.handle, "Ghost: ", 10, y + 4)
	forms.setproperty(temp, "AutoSize", true)
	temp = forms.button(
		form.handle, "Copy from player", useInputsClick,
		forms.getproperty(temp, "Right") + buttonMargin, y,
		100, 23
	)
	form.ghostInputHackButton = temp
	
	temp = forms.button(
		form.handle, "Load bk2m", loadGhostClick,
		forms.getproperty(temp, "Right") + labelMargin, y,
		70, 23
	)
	temp = forms.button(
		form.handle, "Save bk2m", saveCurrentInputsClick,
		forms.getproperty(temp, "Right") + labelMargin, y,
		70, 23
	)
	-- I also want a save-to-bk2m at some point. Although BizHawk doesn't expose a file open function (Lua can still write to files, we just don't have a nice way to let the user choose a save location.) so we might instead copy input to the current movie and let the user save as bk2m manually.

	y = y + 28
	form.drawUnpausedButton = forms.button(
		form.handle, "Draw while unpaused: ON", drawUnpausedClick,
		10, y, 150, 23
	)

	-- Collision view
	--temp = forms.checkbox(kclForm, "freeze location", x + 1, y)
	--forms.addclick(temp, function() viewport.frozen = not viewport.frozen end)
	y = y + 28
	temp = forms.label(form.handle, "3D viewing", 10, y + 3)
	forms.setproperty(temp, "AutoSize", true)
	y = y + 19
	temp = forms.checkbox(form.handle, "draw over screen", 10, y + 3)
	forms.setproperty(temp, "AutoSize", true)
	forms.addclick(temp, kclClick)
	form.delayCheckbox = forms.checkbox(form.handle, "delay", forms.getproperty(temp, "Right") + labelMargin, y + 3)
	forms.setproperty(form.delayCheckbox, "AutoSize", true)
	forms.addclick(form.delayCheckbox, function() mainCamera.useDelay = not mainCamera.useDelay; redraw() end)
	forms.setproperty(form.delayCheckbox, "Checked", true)
	forms.setproperty(form.delayCheckbox, "Visible", false)
	if bizhawkVersion > 9 then
		-- Bug in BizHawk 2.9: We cannot draw on any picturebox if more than one form is open.
		temp = forms.button(
			form.handle, "new window", makeNewKclView,
			forms.getproperty(form.delayCheckbox, "Right") + labelMargin, y, 86, 23
		)
	end

	y = y + 28
	makeCollisionControls(form.handle, mainCamera, 10, y)
end
local hasClosed = false

-- BizHawk ----------------------------
memory.usememorydomain("ARM9 System Bus")

local function main()
	_mkdsinfo_setup()
	while (not shouldExit) or (redrawSeek ~= nil) do
		frame = emu.framecount()
		-- BizHawk 2.10 bug: ancient states don't work!
		if bizhawkVersion == 10 then
			if (frame + 2) % config.ancientStateInterval == 0 then
				tastudio.setmarker(frame + 2, "BizHawk bug workaround")
			elseif tastudio.getmarker(frame + 2) == "BizHawk bug workaround" then
				-- Insert/delete frame will move them around.
				tastudio.removemarker(frame + 2)
			end
		end
		
		if not shouldExit then
			if inRace() then
				_mkdsinfo_run_data()
				_mkdsinfo_run_draw(true)
			else
				_mkdsinfo_run_draw(false)
			end
		end
		
		-- BizHawk shenanigans
		local stopSeeking = false
		if redrawSeek ~= nil and redrawSeek == frame then
			stopSeeking = true
		elseif client.ispaused() then
			-- User has interrupted the rewind seek.
			stopSeeking = true
		end
		if stopSeeking then
			client.pause()
			redrawSeek = nil
			if not shouldExit then
				emu.frameadvance()
			else
				-- The while loop will exit!
			end
		else
			emu.frameadvance()
		end
	end
	if not hasClosed then _mkdsinfo_close() end	
end

gui.clearGraphics("client")
gui.clearGraphics("emucore")
gui.use_surface("emucore")
gui.cleartext()

if tastudio.engaged() then
	bizHawkEventIds[#bizHawkEventIds + 1] = tastudio.onbranchload(branchLoadHandler)
end

main()
