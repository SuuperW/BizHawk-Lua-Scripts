-- The ghost can be made invisible by changing the 0 to -1 on line 16.

local somePointerWithRegionAgnosticAddress = memory.read_u32_le(0x2000B54)
local valueForUSVersion = 0x0216F320
local ptrOffset = somePointerWithRegionAgnosticAddress - valueForUSVersion
local ptrPlayerDataAddr = 0x0217ACF8 + ptrOffset

while true do
	memory.usememorydomain("ARM9 System Bus")
	local ptrPlayerData = memory.read_s32_le(ptrPlayerDataAddr)
	
	if ptrPlayerData ~= 0 then
		local ptrGhostData = ptrPlayerData + 0x5a8

		local offset = 0x384
		memory.write_s16_le(ptrGhostData + offset, 0)
	end
	
	emu.frameadvance()
end
