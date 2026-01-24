local maxChanges = 999 -- Set how many changes the script will check up to. If the game uses more than this many in one frame, the script will not work.
local enableRngHack = false -- if true, touch input coordinates will hack RNG (Y = 1, X = number of states to advance)
local drawLocation = { x = 340, y = 360 }

local prevRng = nil
local totalChanges = nil
local trackingSince = nil
local history = {}
local begins = {}
local currentBegin = nil

local function read_u64(ptr)
	local a = memory.read_u32_le(ptr)
	local b = memory.read_u32_le(ptr + 4)
	return (b << 32) | a
end
local function write_u64(ptr, value)
	local a = value & 0xffffffff
	local b = value >> 32
	memory.write_u32_le(ptr, a)
	memory.write_u32_le(ptr + 4, b)
end
local function readRngContext(ptr)
	return {
		value = read_u64(ptr),
		mul = read_u64(ptr + 8),
		add = read_u64(ptr + 0x10),
		ptr = ptr,
	}
end

local race_status_ptr = memory.read_u32_le(0x21755FC)
-- These names come from HaroohiPals. Idk what they mean.
-- Only "safeRng" affects races during the race.
-- There are temporary generators used to determine CPU combos, seeded with "tick count"
local safeRng = readRngContext(race_status_ptr + 0x47c)
-- "randomRng" is used for the roullete. While it is spinning, the items that scroll through the view are random from randomRng.
local randomRng = readRngContext(race_status_ptr + 0x498)
local stableRng = readRngContext(race_status_ptr + 0x4b0)

local rngToWatch = safeRng

local function nextRngValue(value, context)
	-- Lua does 64-bit integer math!
	return value * context.mul + context.add
end

local function getChangeCount(old, new, max)
	local changes = 0
	for i = 1, max + 1, 1 do
		if old == new then
			break
		end
		old = nextRngValue(old, rngToWatch)
		changes = changes + 1
	end
	
	if (old == new) then
		return { changes = changes, computed = old }
	else
		return { changes = -1, computed = old }
	end
end

local function initialize()
	begins = {}
	begins[1] = {
		frame = emu.framecount(),
		value = read_u64(rngToWatch.ptr),
	}
	
	history = {}
	totalChanges = 0
	trackingSince = emu.framecount()
	prevRng = begins[1].value
	currentBegin = 1
end

local function doRngHack()
	if enableRngHack then
		local input = movie.getinput(emu.framecount() - 1)
		if input["Touch Y"] == 1 then
			local changesToMake = input["Touch X"]
			for i = 1, changesToMake do
				rngState = nextRngValue(rngState, rngToWatch)
			end
			write_u64(rngToWatch.ptr, rngState)
		end
	end
end

local function newBeginning(index)
	for i = #begins, index, -1 do
		begins[i + 1] = begins[i]
	end
	
	trackingSince = emu.framecount()
	totalChanges = 0
	begins[index] = {
		frame = trackingSince,
		value = read_u64(rngToWatch.ptr),
	}
	currentBegin = index
end
local function restoreFromHistory()
	local frame = emu.framecount()
	if frame < begins[1].frame then
		newBeginning(1)
		return true
	end
	
	local haveHistory = history[frame] ~= nil
	for i = 1, #begins do
		local startFrame = begins[i].frame
		local endFrame = 0xffffffff
		if i < #begins then endFrame = begins[i + 1].frame end
		
		if frame >= startFrame and frame < endFrame then
			if haveHistory then
				trackingSince = startFrame
				local totalChanges = 0
				for j = startFrame, frame - 1 do
					totalChanges = totalChanges + history[j]
				end
				-- Validate
				local computed = getChangeCount(begins[i].value, read_u64(rngToWatch.ptr), totalChanges)
				if computed.changes ~= totalChanges then
					print(computed.changes, totalChanges)
					return false
				end
				return true
			else
				newBeginning(i + 1)
				return true
			end
		end
	end
	
	error("unreachable code reached")
	return false
end

local function runNormalRngCheck()
	memory.usememorydomain("ARM9 System Bus")
	local rngState = read_u64(rngToWatch.ptr)
	local _ = getChangeCount(prevRng, rngState, maxChanges)
	local changes = _.changes
	local computed = _.computed
	
	if changes >= 0 then
		if rngState == computed then
			totalChanges = totalChanges + changes
			gui.text(drawLocation.x, drawLocation.y, changes .. " this frame")
			gui.text(drawLocation.x, drawLocation.y + 16, totalChanges .. " since f" .. trackingSince)
			
			history[emu.framecount() - 1] = changes
		else
			print(changes)
			print(rngState)
			print(prevRng)
			error("Unable to compute RNG state change.")
			initialize()
		end
	end
end

local lastFrame = emu.framecount()
local function fn()
	local frame = emu.framecount()
	if frame == lastFrame + 1 then
		runNormalRngCheck()
		doRngHack()
		if #begins > currentBegin and begins[currentBegin + 1].frame == frame then
			-- combine them
			for i = currentBegin + 1, #begins - 1 do
				begins[i] = begins[i + 1]
			end
			begins[#begins] = nil
		end
	else
		local matchesHistory = restoreFromHistory()
		if not matchesHistory then
			error("RNG history mismatch.")
			initialize()
		end
	end
	
	lastFrame = frame
end

local function getHistoryFor(frame, col)
	if col ~= "rng" then return nil end
	
	return history[frame] or " "
end

local function onBranchLoad(index)
	initialize()
	lastFrame = emu.framecount()
end

tastudio.addcolumn("rng", "rng", 30)
tastudio.onqueryitemtext(getHistoryFor)
tastudio.onbranchload(onBranchLoad)

--global
function getrng(asstring)
	if asstring == nil then asstring = true end
	if asstring == true then
		print(string.format("%x", read_u64(rngToWatch.ptr)))
	else
		return read_u64(rngToWatch.ptr)
	end
end

local funcs = {}
funcs[#funcs + 1] = event.onframestart(function() prevRng = read_u64(rngToWatch.ptr) end)
funcs[#funcs + 1] = event.onframeend(fn)

local function clean()
	for i = 1, #funcs do
		event.unregisterbyid(funcs[i])
	end
end
event.onexit(clean)

initialize()
while true do
	emu.frameadvance()
end
