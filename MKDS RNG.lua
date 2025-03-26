local maxChanges = 9999 -- Set how many changes the script will check up to. If the game uses more than this many in one frame, the script will not work.
local drawLocation = { x = 340, y = 360 }

local enableRngHack = false -- Lets you hack RNG with touch inputs. (Y = 1, X = number of states to advance)

local prevRng = nil
local totalChanges = 0
local trackingSince = emu.framecount()
local originalState = nil
local history = {}

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
-- It seems like only "safeRng" is actually used.
local safeRng = readRngContext(race_status_ptr + 0x47c)
-- Oh, "randomRng" is actually used for the roullete. While it is spinning, the items that scroll through the view are random from randomRng.
local randomRng = readRngContext(race_status_ptr + 0x498)
local stableRng = readRngContext(race_status_ptr + 0x4b0)

local rngToWatch = safeRng

local function nextRngValue(value, context)
	-- Lua does 64-bit integet math!
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

local function fn()
	local rngState = read_u64(rngToWatch.ptr)
	if prevRng ~= nil then
		local _ = getChangeCount(prevRng, rngState, maxChanges)
		local changes = _.changes
		prevRng = _.computed
		
		if changes >= 0 then
			if rngState ~= prevRng then
				print(changes)
				print(rngState)
				print(prevRng)
				error("Unable to compute RNG state change.")
			end
			totalChanges = totalChanges + changes
			gui.text(drawLocation.x, drawLocation.y, changes .. " this frame")
			gui.text(drawLocation.x, drawLocation.y + 16, totalChanges .. " since f" .. trackingSince)
			
			history[emu.framecount()] = changes
		elseif changes == -1 then
			-- Did we rewind?
			local rewindCheck = getChangeCount(originalState, rngState, totalChanges)
			if rewindCheck.changes == -1 then
				print("Exceeded max RNG state changes per frame.")
				totalChanges = 0
				trackingSince = emu.framecount()
				originalState = rngState
				history[emu.framecount()] = "seeded"
			else
				totalChanges = rewindCheck.changes
				gui.text(drawLocation.x, drawLocation.y, "rewind detected")
				gui.text(drawLocation.x, drawLocation.y + 16, totalChanges .. " since f" .. trackingSince)
			end
		end
	else
		originalState = rngState
	end
	
	prevRng = rngState
	
	-- Poke for the next frame?
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

local function getHistoryFor(frame, col)
	if col ~= "rng" then return nil end
	
	return history[frame] or " "
end

local function onBranchLoad(index)
	history = {}
end

memory.usememorydomain("ARM9 System Bus")
tastudio.addcolumn("rng", "rng", 30)
tastudio.onqueryitemtext(getHistoryFor)
tastudio.onbranchload(onBranchLoad)

while true do
	fn()
	emu.frameadvance()
end