-- Pointer internationalization -------
-- This is intended to make the script compatible with most ROM regions and ROM hacks.
-- This is not well-tested. There are some known exceptions, such as Korean version has different locations for checkpoint stuff.
local somePointerWithRegionAgnosticAddress = memory.read_u32_le(0x2000B54)
local valueForUSVersion = 0x0216F320
local ptrOffset = somePointerWithRegionAgnosticAddress - valueForUSVersion
-- Base addresses are valid for the US Version
local addrs = {
	ptrRacerData = 0x0217ACF8 + ptrOffset,
	ptrPlayerInputs = 0x02175630 + ptrOffset,
	ptrGhostInputs = 0x0217568C + ptrOffset,
	ptrItemInfo = 0x0217BC2C + ptrOffset,
	ptrRaceTimers = 0x0217AA34 + ptrOffset,
	ptrMissionInfo = 0x021A9B70 + ptrOffset,
	ptrObjStuff = 0x0217B588 + ptrOffset,
	racerCount = 0x0217ACF4 + ptrOffset,
	ptrSomeRaceData = 0x021759A0 + ptrOffset,
	ptrCheckNum = 0x021755FC + ptrOffset,
	ptrCheckData = 0x02175600 + ptrOffset,
	ptrScoreCounters = 0x0217ACFC + ptrOffset,
	collisionData = 0x0217b5f4 + ptrOffset,
	ptrCurrentCourse = 0x23cdcd8 + ptrOffset,
	ptrCamera = 0x217AA4C + ptrOffset,
	ptrVisibilityStuff = 0x217AE90 + ptrOffset,
	cameraThing = 0x207AA24 + ptrOffset,
	ptrBattleController = 0x0217b1dc + ptrOffset,
}
---------------------------------------
-- These have the same address in E and U versions.
-- Not sure about other versions. K +0x5224 for car at least.
local hitboxFuncs = {
	car = memory.read_u32_le(0x2158ad4),
	bumper = memory.read_u32_le(0x209c190),
	clockHand = memory.read_u32_le(0x2159158),
	pendulum = memory.read_u32_le(0x21592e8),
	rockyWrench = memory.read_u32_le(0x2095fe8),
}
---------------------------------------

-- get_thing: Read thing from a byte array.
-- We do this because it is more performant than making many BizHawk API calls.
local function get_u32(data, offset)
	return data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)
end
local function get_s32(data, offset)
	local u = data[offset] | (data[offset + 1] << 8) | (data[offset + 2] << 16) | (data[offset + 3] << 24)
	return u - ((data[offset + 3] & 0x80) << 25)
end
local function get_u16(data, offset)
	return data[offset] | (data[offset + 1] << 8)
end
local function get_s16(data, offset)
	local u = data[offset] | (data[offset + 1] << 8)
	return u - ((data[offset + 1] & 0x80) << 9)
end

local function get_pos(data, offset)
	return {
		get_s32(data, offset),
		get_s32(data, offset + 4),
		get_s32(data, offset + 8),
	}
end
local function get_pos_16(data, offset)
	return {
		get_s16(data, offset),
		get_s16(data, offset + 2),
		get_s16(data, offset + 4),
	}
end
local function get_quaternion(data, offset)
	return {
		k = get_s32(data, offset),
		j = get_s32(data, offset + 4),
		i = get_s32(data, offset + 8),
		r = get_s32(data, offset + 12),
	}
end

-- Read structures
local function read_pos_16(addr)
	local d = memory.read_bytes_as_array(addr, 6)
	return {
		get_s16(d, 1),
		get_s16(d, 3),
		get_s16(d, 5),
	}
end

local function read_pos(addr)
	local data = memory.read_bytes_as_array(addr, 12)
	return get_pos(data, 1)
end
local function read_quaternion(addr)
	return {
		k = memory.read_s32_le(addr),
		j = memory.read_s32_le(addr + 4),
		i = memory.read_s32_le(addr + 8),
		r = memory.read_s32_le(addr + 12),
	}
end

_export = {
	addrs = addrs,
	hitboxFuncs = hitboxFuncs,
	get_u32 = get_u32,
	get_s32 = get_s32,
	get_u16 = get_u16,
	get_s16 = get_s16,
	get_pos = get_pos,
	get_pos_16 = get_pos_16,
	get_quaternion = get_quaternion,
	read_pos = read_pos,
	read_pos_16 = read_pos_16,
	read_quaternion = read_quaternion,
}