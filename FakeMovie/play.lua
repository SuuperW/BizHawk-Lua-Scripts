-- Touch inputs do not work by default!
-- To make touch inputs work, you must do two things:
-- 1) Disable touch interpolation under NDS Sync Settings (unless the movie actually expects it to be enabled)
-- 2) Un-bind TouchX and TouchY controls, as these would overwrite the Lua-set values.

dofile "json.lua"

local fs = io.open("fakemovieinputs.json", "r")
if fs == nil then error("could not open fakemovieinputs.json") end
local jsonStr = fs:read("a")
io.close(fs)

local inputs = json.parse(jsonStr)
if inputs == nil then error("invalid movie inputs") end
while true do
	local frame = tostring(emu.framecount()) -- it's a table (string keys), not an array	
	joypad.set(inputs[frame])
	joypad.setanalog(inputs[frame])
	emu.frameadvance()
end
