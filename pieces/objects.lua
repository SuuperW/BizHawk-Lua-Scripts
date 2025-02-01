local Vector = _imports.Vector
local Memory = _imports.Memory
local read_pos = Memory.read_pos
local get_u32 = Memory.get_u32
local get_s32 = Memory.get_s32
local get_u16 = Memory.get_u16

local function mul_fx(a, b)
	return a * b // 0x1000
end

local ptrObjArray = nil
local function loadCourseData()
	ptrObjArray = memory.read_s32_le(Memory.addrs.ptrObjStuff + 0x10)
end


local function getBoxyPolygons(center, directions, sizes, sizes2)
	if sizes2 == nil then sizes2 = sizes end
	local offsets = {
		x1 = Vector.multiply(directions[1], sizes[1] / 0x1000),
		y1 = Vector.multiply(directions[2], sizes[2] / 0x1000),
		z1 = Vector.multiply(directions[3], sizes[3] / 0x1000),
		x2 = Vector.multiply(directions[1], sizes2[1] / 0x1000),
		y2 = Vector.multiply(directions[2], sizes2[2] / 0x1000),
		z2 = Vector.multiply(directions[3], sizes2[3] / 0x1000),
	}
	
	local s = Vector.subtract
	local a = Vector.add
	local verts = {
		s(s(s(center, offsets.x2), offsets.y2), offsets.z2),
		a(s(s(center, offsets.x2), offsets.y2), offsets.z1),
		s(a(s(center, offsets.x2), offsets.y1), offsets.z2),
		a(a(s(center, offsets.x2), offsets.y1), offsets.z1),
		s(s(a(center, offsets.x1), offsets.y2), offsets.z2),
		a(s(a(center, offsets.x1), offsets.y2), offsets.z1),
		s(a(a(center, offsets.x1), offsets.y1), offsets.z2),
		a(a(a(center, offsets.x1), offsets.y1), offsets.z1),
	}
	return {
		{ verts[1], verts[5], verts[7], verts[3] },
		{ verts[1], verts[5], verts[6], verts[2] },
		{ verts[1], verts[3], verts[4], verts[2] },
		{ verts[8], verts[4], verts[2], verts[6] },
		{ verts[8], verts[4], verts[3], verts[7] },
		{ verts[8], verts[6], verts[5], verts[7] },
	}
end
local function getCylinderPolygons(center, directions, radius, h1, h2)
	local offsets = {
		Vector.multiply(directions[1], radius / 0x1000),
		Vector.multiply(directions[2], h1 / 0x1000),
		Vector.multiply(directions[3], radius / 0x1000),
		Vector.multiply(directions[2], -h2 / 0x1000),
	}
	
	local a = Vector.add
	local m = Vector.multiply
	local norm = Vector.normalize_float
	radius = radius / 0x1000
	local around = {
		offsets[1],
		m(norm(a(m(offsets[1], 2), offsets[3])), radius),
		m(norm(a(offsets[1], offsets[3])), radius),
		m(norm(a(offsets[1], m(offsets[3], 2))), radius),
		offsets[3],
		m(norm(a(m(offsets[1], -1), m(offsets[3], 2))), radius),
		m(norm(a(m(offsets[1], -1), offsets[3])), radius),
		m(norm(a(m(offsets[1], -2), offsets[3])), radius),
	}
	local count = #around
	for i = 1, count do
		around[#around + 1] = m(around[i], -1)
	end
	
	local tc = Vector.add(center, offsets[2])
	local bc = Vector.add(center, offsets[4])
	local vertsT = {}
	local vertsB = {}
	for i = 1, #around do
		vertsT[i] = a(tc, around[i])
		vertsB[i] = a(bc, around[i])
	end
	
	local polys = {}
	for i = 1, #around - 1 do
		polys[i] = { vertsT[i], vertsT[i + 1], vertsB[i + 1], vertsB[i] }
	end
	polys[#polys + 1] = vertsT
	polys[#polys + 1] = vertsB
	return polys
end

local mapObjTypes = {}
local t = mapObjTypes
if true then -- I just want to collapse this block in my editor.
	t[0] = "follows player"
	t[11] = "STOP! signage"; t[14] = "puddle";
	t[101] = "item box"; t[102] = "post"; t[103] = "wooden crate";
	t[104] = "coin"; t[106] = "shine";
	t[110] = "gate trigger";
	t[201] = "moving item box"; t[202] = "moving block";
	t[203] = "gear"; t[204] = "bridge";
	t[205] = "clock hand"; t[206] = "gear";
	t[207] = "pendulum"; t[208] = "rotating floor";
	t[209] = "rotating bridge"; t[210] = "roulette";
	t[0x12e] = "coconut tree"; t[0x12f] = "pipe";
	t[0x130] = "wumpa-fruit tree";
	t[0x138] = "striped tree";
	t[0x145] = "autumn tree"; t[0x146] = "winter tree";
	t[0x148] = "palm tree";
	t[0x14f] = "pinecone tree"; t[0x150] = "beanstalk";
	t[0x156] = "N64 winter tree";
	t[401] = "goomba"; t[402] = "giant snowball";
	t[403] = "thwomp";
	t[405] = "bus"; t[406] = "chain chomp";
	t[407] = "chain chomp post"; t[408] = "leaping fireball";
	t[409] = "mole"; t[410] = "car";
	t[411] = "cheep cheep"; t[412] = "truck";
	t[413] = "snowman"; t[414] = "coffin";
	t[415] = "bats";
	t[418] = "bullet bill"; t[419] = "walking tree";
	t[420] = "flamethrower"; t[421] = "stray chain chomp";
	t[422] = "piranha plant"; t[428] = "rocky wrench";
	t[424] = "bumper"; t[425] = "flipper";
	t[428] = "crab";
	t[431] = "fireballs"; t[432] = "pinball";
	t[433] = "boulder"; t[434] = "pokey";
	t[436] = "strawberry bumper"; t[437] = "Strawberry Bumper";
	t[501] = "bully"; t[502] = "Chief Chilly";
	t[0x1f8] = "King Bomb-omb";
	t[0x1fb] = "Eyerok"; t[0x1fd] = "King Boo";
	t[0x1fe] = "Wiggler";
end

local FLAG_DYNAMIC = 0x1000
local FLAG_MAPOBJ  = 0x2000
local FLAG_ITEM    = 0x4000
local FLAG_RACER   = 0x8000

local function getBoxyDistances(obj, pos, radius)
	local posDelta = Vector.subtract(pos, obj.dynPos)
	
	local dir = obj.orientation
	local sizes = obj.sizes
	local orientedPosDelta = {
		Vector.dotProduct_t(posDelta, dir[1]),
		Vector.dotProduct_t(posDelta, dir[2]),
		Vector.dotProduct_t(posDelta, dir[3]),
	}
	local orientedDistanceTo = {
		math.abs(orientedPosDelta[1]) - radius - sizes[1],
		math.abs(orientedPosDelta[2]) - radius - sizes[2],
		math.abs(orientedPosDelta[3]) - radius - sizes[3],
	}
	local outsideTheBox = 0
	for i = 1, 3 do
		if orientedDistanceTo[i] > 0 then
			outsideTheBox = outsideTheBox + orientedDistanceTo[i] * orientedDistanceTo[i]
		end
	end
	local totalDistance = nil
	if outsideTheBox ~= 0 then
		totalDistance = math.sqrt(outsideTheBox)
	else
		totalDistance = math.max(orientedDistanceTo[1], orientedDistanceTo[2], orientedDistanceTo[3])
	end
	return {
		orientedDistanceTo[1],
		orientedDistanceTo[2],
		orientedDistanceTo[3],
		totalDistance,
	}
end
local function getCylinderDistances(obj, pos, radius)
	local posDelta = Vector.subtract(pos, obj.dynPos)
	
	local dir = obj.orientation
	local orientedPosDelta = {
		Vector.dotProduct_t(posDelta, dir[1]),
		Vector.dotProduct_t(posDelta, dir[2]),
		Vector.dotProduct_t(posDelta, dir[3]),
	}
	orientedPosDelta = {
		h = math.sqrt(orientedPosDelta[1] * orientedPosDelta[1] + orientedPosDelta[3] * orientedPosDelta[3]),
		v = orientedPosDelta[2]
	}
	local bHeight = obj.bHeight
	if bHeight == nil then bHeight = obj.height end
	local orientedDistanceTo = {
		math.abs(orientedPosDelta.h) - radius - obj.objRadius,
		math.max(
			orientedPosDelta.v - radius - obj.height,
			-(orientedPosDelta.v + radius + bHeight)
		),
	}
	local outside = 0
	for i = 1, 2 do
		if orientedDistanceTo[i] > 0 then
			outside = outside + orientedDistanceTo[i] * orientedDistanceTo[i]
		end
	end
	local totalDistance = nil
	if outside ~= 0 then
		totalDistance = math.sqrt(outside)
	else
		totalDistance = math.max(orientedDistanceTo[1], orientedDistanceTo[2])
	end
	return {
		h = math.floor(orientedDistanceTo[1]),
		v = math.floor(orientedDistanceTo[2]),
		d = totalDistance,
	}
end

local function getDetailsForBoxyObject(obj)
	obj.boxy = true
	if obj.hitboxFunc == Memory.hitboxFuncs.car then
		obj.sizes = read_pos(obj.ptr + 0x114)
		obj.backSizes = {
			obj.sizes[1],
			0,
			memory.read_s32_le(obj.ptr + 0x120),
		}
	elseif obj.hitboxFunc == Memory.hitboxFuncs.clockHand then
		obj.sizes = read_pos(obj.ptr + 0x58)
		obj.backSizes = Vector.copy(obj.sizes)
		obj.backSizes[3] = 0
	elseif obj.hitboxFunc == Memory.hitboxFuncs.pendulum then
		obj.sizes = {
			obj.objRadius,
			obj.objRadius,
			memory.read_s32_le(obj.ptr + 0x108),
		}
	elseif obj.hitboxFunc == Memory.hitboxFuncs.rockyWrench then
		obj.sizes = {
			obj.objRadius,
			memory.read_s32_le(obj.ptr + 0xa0),
			obj.objRadius,
		}
	else
		obj.sizes = read_pos(obj.ptr + 0x58)
	end
	obj.dynPos = obj.objPos
	obj.polygons = getBoxyPolygons(obj.objPos, obj.orientation, obj.sizes, obj.backSizes)
end
local function getDetailsForCylinder2Object(obj, isBumper)
	obj.cylinder2 = true
	obj.dynPos = obj.objPos -- It may not be dynamic, but getCylinderDistances expexts this
	
	if isBumper then
		obj.bHeight = 0
		if memory.read_u16_le(obj.ptr + 2) & 0x800 == 0 and memory.read_u32_le(obj.ptr + 0x11c) == 1 then
			obj.objRadius = mul_fx(obj.objRadius, memory.read_u32_le(obj.ptr + 0xbc))
		end
	else
		obj.bHeight = obj.height
	end
	
	obj.polygons = getCylinderPolygons(obj.objPos, obj.orientation, obj.objRadius, obj.height, obj.bHeight)
end
local function getDetailsForDynamicBoxyObject(obj)
	obj.sizes = read_pos(obj.ptr + 0x100)
	obj.dynPos = read_pos(obj.ptr + 0xf4)
	obj.backSizes = Vector.copy(obj.sizes)
	obj.backSizes[3] = memory.read_s32_le(obj.ptr + 0x10c)
	obj.polygons = getBoxyPolygons(obj.dynPos, obj.orientation, obj.sizes, obj.backSizes)
end
local function getDetailsForDynamicCylinderObject(obj)
	obj.objRadius = memory.read_s32_le(obj.ptr + 0x100)
	obj.height = memory.read_s32_le(obj.ptr + 0x104)
	obj.dynPos = read_pos(obj.ptr + 0xf4)
	obj.polygons = getCylinderPolygons(obj.dynPos, obj.orientation, obj.objRadius, obj.height, obj.height)
end
local function getMapObjDetails(obj)
	local objPtr = obj.ptr
	local typeId = memory.read_u16_le(objPtr)
	obj.typeId = typeId
	obj.type = mapObjTypes[typeId] or ("unknown " .. typeId)
	obj.boxy = false
	obj.cylinder = false
	
	obj.objRadius = memory.read_s32_le(objPtr + 0x58)
	obj.height = memory.read_s32_le(objPtr + 0x5C)
	obj.orientation = {
		read_pos(obj.ptr + 0x28),
		read_pos(obj.ptr + 0x34),
		read_pos(obj.ptr + 0x40),
	}

	-- Hitbox
	local hitboxType = ""
	if memory.read_u16_le(objPtr + 2) & 1 == 0 then
		local maybePtr = memory.read_s32_le(objPtr + 0x98)
		local hbType = 0
		if maybePtr > 0 then
			-- The game has no null check, but I don't want to keep seeing the "attempted read outside memory" warning
			hbType = memory.read_s32_le(maybePtr + 8)
		end
		if hbType == 0 or hbType > 5 or hbType < 0 then
			hitboxType = ""
		elseif hbType == 1 then
			hitboxType = "spherical"
		elseif hbType == 2 then
			hitboxType = "cylindrical"
			obj.polygons = getCylinderPolygons(obj.objPos, obj.orientation, obj.objRadius, obj.height, obj.height)
		elseif hbType == 3 then
			hitboxType = "cylinder2" -- I can't find an object in game that directly uses this.
			getDetailsForCylinder2Object(obj, false)
		elseif hbType == 4 then
			hitboxType = "boxy"
			getDetailsForBoxyObject(obj)
		elseif hbType == 5 then
			hitboxType = "custom" -- Object defines its own collision check function
			obj.chb = memory.read_u32_le(objPtr + 0x98)
			obj.hitboxFunc = memory.read_u32_le(obj.chb + 0x18)
			if obj.hitboxFunc == Memory.hitboxFuncs.car then
				hitboxType = "boxy"
				getDetailsForBoxyObject(obj)
			elseif obj.hitboxFunc == Memory.hitboxFuncs.bumper then
				hitboxType = "cylinder2"
				getDetailsForCylinder2Object(obj, true)
			elseif obj.hitboxFunc == Memory.hitboxFuncs.clockHand then
				hitboxType = "boxy"
				getDetailsForBoxyObject(obj)
			elseif obj.hitboxFunc == Memory.hitboxFuncs.pendulum then
				hitboxType = "spherical"
				obj.objRadius = memory.read_s32_le(obj.ptr + 0x104)
				getDetailsForBoxyObject(obj)
				obj.multiBox = true
			elseif obj.hitboxFunc == Memory.hitboxFuncs.rockyWrench then
				if memory.read_u8(obj.ptr + 0xb0) == 1 then
					hitboxType = "no hitbox"
				else
					hitboxType = "spherical"
					obj.multiBox = true
					getDetailsForBoxyObject(obj)
				end
			else
				hitboxType = hitboxType .. " " .. string.format("%x", obj.hitboxFunc)
			end
		end
	end
	if hitboxType == "" then hitboxType = "no hitbox" end
	obj.hitboxType = hitboxType
end
local itemNames = { -- IDs according to list of itemsets
	"red shell", "banana", "mushroom",
	"star", "blue shell", "lightning",
	"fake item box", "itembox?", "bomb",
	"blooper", "boo", "gold mushroom",
	"bullet bill",
}
itemNames[0] = "green shell"
local function getItemDetails(obj)
	local ptr = obj.ptr
	obj.itemRadius = memory.read_s32_le(ptr + 0xE0)
	obj.objRadius  = memory.read_s32_le(ptr + 0xDC)
	obj.itemTypeId = memory.read_s32_le(ptr + 0x44)
	obj.itemName = itemNames[obj.itemTypeId]
	obj.itemPos = obj.objPos
	obj.velocity = read_pos(ptr + 0x5C)
	obj.hitboxType = "item"
end
local function getRacerObjDetails(obj)
	obj.objRadius = memory.read_s32_le(obj.ptr + 0x1d0)
	obj.itemRadius = obj.objRadius
	obj.itemPos = read_pos(obj.ptr + 0x1d8)
	obj.type = "racer"
	obj.hitboxType = "item"
end
local function isCoinCollected(objPtr)
	return memory.read_u16_le(objPtr + 2) & 0x01 ~= 0
end
local function isGhost(objPtr)
	local flags7c = memory.read_u8(objPtr + 0x7C)
	return flags7c & 0x04 ~= 0
end
local function getObjectDetails(obj)
	obj.basePos = obj.objPos
	local flags = obj.flags
	if flags & FLAG_MAPOBJ ~= 0 then
		obj.isMapObject = true
		getMapObjDetails(obj)
	elseif flags & FLAG_ITEM ~= 0 then
		obj.isItem = true
		getItemDetails(obj)
	elseif flags & FLAG_RACER ~= 0 then
		getRacerObjDetails(obj)
	else
		return
	end

	if flags & 0x1000 ~= 0 then
		obj.dynamic = true
		local aCodePtr = memory.read_u8(obj.ptr + 0x134)
		if aCodePtr == 0 then
			obj.dynamicType = "boxy"
			obj.boxy = true
			getDetailsForDynamicBoxyObject(obj)
		elseif aCodePtr == 1 then
			obj.dynamicType = "cylinder"
			getDetailsForDynamicCylinderObject(obj)
		end
		if obj.dynamicType ~= nil then
			if obj.hitboxType == "no hitbox" then
				obj.hitboxType = "dynamic " .. obj.dynamicType
			else
				obj.hitboxType = obj.hitboxType .. " + " .. obj.dynamicType
			end
		end
	else
		obj.dynamic = false
	end
end
local function getNearbyObjects(racer, dist)
	local maxCount = memory.read_u16_le(Memory.addrs.ptrObjStuff + 0x08)
	local count = 0
	local itemsThatAreObjs = {}

	-- get basic info
	local nearbyObjects = {}
	local objData = memory.read_bytes_as_array(ptrObjArray + 1, 0x1c * 255 - 1)
	--objData[0] = memory.read_u8(ptrObjArray)
	for id = 0, 255 do -- 255: ?? Idk what max is. "maxCount" can't be used because the array we look through can have holes
		local current = id * 0x1c
		local objPtr = get_u32(objData, current + 0x18)
		local flags = get_u16(objData, current + 0x14)

		if objPtr ~= 0 then
			count = count + 1
			-- flag 0x0200: deactivated or something
			if flags & 0x200 == 0 then
				local skip = false
				local obj = {
					id = id,
					objPos = read_pos(get_s32(objData, current + 0xC)),
					flags = flags,
					ptr = objPtr,
				}
				if flags & FLAG_MAPOBJ ~= 0 then
					obj.typeId = memory.read_s16_le(obj.ptr)
					if obj.typeId == 0x68 and isCoinCollected(objPtr) then
						skip = true
					end
				elseif flags & FLAG_RACER ~= 0 then
					if isGhost(objPtr) or objPtr == racer.ptr then
						skip = true
					end
				elseif flags & FLAG_ITEM ~= 0 then
					itemsThatAreObjs[objPtr] = true
				elseif flags & FLAG_DYNAMIC == 0 then
					skip = true
				end
				if not skip then
					local racerPos = racer.objPos
					if flags & FLAG_ITEM ~= 0 then
						racerPos = racer.itemPos
					elseif flags & FLAG_RACER ~= 0 then
						racerPos = racer.itemPos
						obj.objPos = read_pos(obj.ptr + 0x1d8)
					end
					local dx = racerPos[1] - obj.objPos[1]
					local dz = racerPos[3] - obj.objPos[3]
					local d = dx * dx + dz * dz
					if d <= dist then
						nearbyObjects[#nearbyObjects + 1] = obj
					else
						if (obj.typeId == 209 and d <= 9e13) or (obj.typeId == 11 and d < 1.2e13) then
							-- obj 209: rotating bridge in Bowser's Castle: it's huge
							-- obj 11: stop signage, they are huge boxes
							nearbyObjects[#nearbyObjects + 1] = obj
						end
					end
				end
			end
			
			if count == maxCount then
				break
			end
		end
	end

	-- items
	local setsPtr = memory.read_u32_le(Memory.addrs.ptrItemSets)
	for iSet = 0, 13 do
		local sp = setsPtr + iSet*0x44
		local setPtr = memory.read_u32_le(sp + 4)
		local setCount = memory.read_u16_le(sp + 0x10)
		for i = 0, setCount - 1 do
			local itemObj = {
				ptr = memory.read_u32_le(setPtr + i*4),
				flags = FLAG_ITEM,
			}
			if itemsThatAreObjs[itemObj.ptr] == nil then
				local itemFlags = memory.read_u32_le(itemObj.ptr + 0x74)
				if itemFlags & 0x0080000 == 0 then -- Idk what these flags mean
					-- others set were 0x0020080
					itemObj.objPos = read_pos(itemObj.ptr + 0x50)
					local dx = racer.itemPos[1] - itemObj.objPos[1]
					local dz = racer.itemPos[3] - itemObj.objPos[3]
					local d = dx * dx + dz * dz
					if d <= dist then
						nearbyObjects[#nearbyObjects + 1] = itemObj
					end
				end
			end
		end
	end
	
	-- get details for nearby objects
	local nearest = nil
	for i = 1, #nearbyObjects do
		local obj = nearbyObjects[i]

		getObjectDetails(obj)

		if obj.hitboxType == "cylindrical" then
			local relative = Vector.subtract(racer.objPos, obj.objPos)
			local distance = math.sqrt(relative[1] * relative[1] + relative[3] * relative[3])
			obj.distance = distance - racer.objRadius - obj.objRadius
			-- TODO: Check vertical distance?
		elseif obj.hitboxType == "spherical" then
			local relative = Vector.subtract(racer.objPos, obj.objPos)
			local distance = math.sqrt(relative[1] * relative[1] + relative[2] * relative[2] + relative[3] * relative[3])
			obj.distance = distance - racer.objRadius - obj.objRadius
			-- Special object: pendulum
			if obj.hitboxFunc == Memory.hitboxFuncs.pendulum then
				relative = Vector.subtract(racer.objPos, obj.objPos)
				obj.distanceComponents = {
					h = math.floor(obj.distance),
					v = Vector.dotProduct_t(relative, obj.orientation[3]) - racer.objRadius - obj.sizes[3],
				}
				obj.distance = math.max(obj.distanceComponents.h, obj.distanceComponents.v)
			end
		elseif obj.hitboxType == "item" then
			local relative = Vector.subtract(racer.itemPos, obj.itemPos)
			local distance = math.sqrt(relative[1] * relative[1] + relative[2] * relative[2] + relative[3] * relative[3])
			obj.distance = distance - racer.itemRadius - obj.itemRadius
		elseif obj.boxy then
			obj.distanceComponents = getBoxyDistances(obj, racer.objPos, racer.objRadius)
			-- TODO: Do all dynamic boxy objects have racer-spherical hitboxes?
			-- Also TODO: Find a nicer way to display this maybe?
			obj.innerDistComps = getBoxyDistances(obj, racer.objPos, 0)
			obj.distance = obj.distanceComponents[4]
		elseif obj.dynamicType == "cylinder" or obj.hitboxType == "cylinder2" then
			obj.distanceComponents = getCylinderDistances(obj, racer.objPos, racer.objRadius)
			obj.distance = obj.distanceComponents.d
		else
			local relative = Vector.subtract(racer.objPos, obj.objPos)
			obj.distance = math.sqrt(relative[1] * relative[1] + relative[2] * relative[2] + relative[3] * relative[3])
		end
		
		if nearest == nil or obj.distance < nearest.distance then
			nearest = obj
		end
	end

	return { nearbyObjects, nearest }
end

_export = {
	loadCourseData = loadCourseData,
	getNearbyObjects = getNearbyObjects,
	isGhost = isGhost,
	getBoxyPolygons = getBoxyPolygons,
	mapObjTypes = mapObjTypes,
}
