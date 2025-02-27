local Memory = _imports.Memory
local Vector = _imports.Vector
local get_pos = Memory.get_pos
local get_u32 = Memory.get_u32
local get_s32 = Memory.get_s32
local get_u16 = Memory.get_u16
local get_s16 = Memory.get_s16
local get_pos_16 = Memory.get_pos_16

local someCourseData = nil

local function mul_fx(a, b)
	return a * b // 0x1000
end

local SOUND_TRIGGER = 4
local FLOOR_NO_RACERS = 13
local WALL_NO_RACERS = 14
local EDGE_WALL = 16
local RECALCULATE_ROUTE = 22

local skippableTypes = (1 << SOUND_TRIGGER) | (1 << FLOOR_NO_RACERS) | (1 << WALL_NO_RACERS) | (1 << RECALCULATE_ROUTE)

local function _getNearbyTriangles(pos)
	if someCourseData == nil or triangles == nil then error("nil course data") end
	-- Read map of position -> nearby triangle IDs
	local boundary = get_pos(someCourseData, 0x14)
	if pos[1] < boundary[1] or pos[2] < boundary[2] or pos[3] < boundary[3] then
		return {}
	end
	local shift = someCourseData[0x2C]
	local fb = {
		(pos[1] - boundary[1]) >> 12,
		(pos[2] - boundary[2]) >> 12,
		(pos[3] - boundary[3]) >> 12,
	}
	local base = get_u32(someCourseData, 0xC)
	local a = base
	local b = a + 4 * (
		((fb[1] >> shift)) |
		((fb[2] >> shift) << someCourseData[0x30]) |
		((fb[3] >> shift) << someCourseData[0x34])
	)
	if b >= 0x02800000 then
		-- This may happen during course loads: the data we're trying to read isn't initialized yet. ... but we shouldn't ever use this function at that time
		error("Attempted to get triangles before course loaded.")
	end
	b = get_u32(collisionMap, b - base)
	local safety = 0
	while b < 0x80000000 do
		safety = safety + 1
		if safety > 1000 then error("infinite loop: reading nearby triangle map") end
		a = a + b
		shift = shift - 1
		b = a + 4 * (
			(((fb[1] >> shift) & 1)) |
			(((fb[2] >> shift) & 1) << 1) |
			(((fb[3] >> shift) & 1) << 2)
		)
		b = get_u32(collisionMap, b - base)
	end
	a = a + (b - 0x80000000) + 2

	-- a now points to first triangle ID
	local nearby = {}
	local index = get_u16(collisionMap, a - base)
	safety = 0
	while index ~= 0 do
		nearby[#nearby + 1] = triangles[index]
		index = get_u16(collisionMap, a + 2 * #nearby - base)
		safety = safety + 1
		if safety > 1000 then
			error("infinite loop: reading nearby triangle list")
		end
	end
	return nearby
end
local _mergeSet = {}
local function merge(l1, l2)
	for i = 1, #l2 do
		local v = l2[i]
		if _mergeSet[v] == nil then
			l1[#l1 + 1] = v
			_mergeSet[v] = true
		end
	end
end
local function getNearbyTriangles(pos, extraRenderDistance)
	if extraRenderDistance == nil then
		return _getNearbyTriangles(pos)
	end

	_mergeSet = {}
	local nearby = {}
	-- How many units should we move at a time?
	local step = 100 * 0x1000
	for iX = -extraRenderDistance, extraRenderDistance do
		for iY = -extraRenderDistance, extraRenderDistance do
			for iZ = -extraRenderDistance, extraRenderDistance do
				local p = {
					pos[1] + iX * step,
					pos[2] + iY * step,
					pos[3] + iZ * step,
				}
				merge(nearby, _getNearbyTriangles(p))
			end
		end
	end
	
	return nearby
end
local function updateMinMax(current, new)
	current.min[1] = math.min(current.min[1], new[1])
	current.min[2] = math.min(current.min[2], new[2])
	current.min[3] = math.min(current.min[3], new[3])
	current.max[1] = math.max(current.max[1], new[1])
	current.max[2] = math.max(current.max[2], new[2])
	current.max[3] = math.max(current.max[3], new[3])
end
local function someKindOfTransformation(a, d2, d1, v2, v1)
	-- FUN_01fff434
	local m = 0
	if a ~= 0x1000 and a ~= -0x1000 then
		m = math.floor((mul_fx(a, d1) - d2) / (mul_fx(a, a) - 0x1000) * 0x1000 + 0.5)
	else
		-- Divide by zero. NDS returns either 1 or -1.
		-- MKDS will then round + bit shift (for fx32 precision reasons) and give 0.
	end
	local n = d1 - mul_fx(m, a)
	
	local out = Vector.add(
		Vector.multiply_t(v2, m),
		Vector.multiply_t(v1, n)
	)
	
	return out
end
local function getSurfaceDistanceData(toucher, surface)
	local data = {}
	local radius = toucher.radius

	local relativePos = Vector.subtract(toucher.pos, surface.vertex[1])
	local previousPos = toucher.previousPos and Vector.subtract(toucher.previousPos, surface.vertex[1])
	local upDistance = Vector.dotProduct_t(relativePos, surface.surfaceNormal)
	local inDistance = Vector.dotProduct_t(relativePos, surface.inVector)
	local planeDistances = {
		{
			d = Vector.dotProduct_t(relativePos, surface.outVector[1]),
			v = surface.outVector[1],
		}, {
			d = Vector.dotProduct_t(relativePos, surface.outVector[2]),
			v = surface.outVector[2],
		}, {
			d = inDistance - surface.triangleSize,
			v = surface.outVector[3],
		}
	}
	table.sort(planeDistances, function(a, b) return a.d > b.d end )

	data.isBehind = upDistance < 0
	if previousPos ~= nil and Vector.dotProduct_t(previousPos, surface.surfaceNormal) < 0 then
		data.wasBehind = true
		if Vector.dotProduct_t(previousPos, surface.outVector[1]) <= 0 and Vector.dotProduct_t(previousPos, surface.outVector[2]) <= 0 and Vector.dotProduct_t(previousPos, surface.inVector) <= surface.triangleSize then
			data.wasInside = true
		end
	end
	
	data.distanceVector = Vector.multiply(surface.surfaceNormal, -upDistance / 0x1000)
	local edgeDistSq
	local distanceOffset = nil
	if planeDistances[1].d <= 0 then
		-- fully inside
		edgeDistSq = 0
		data.dist2d = 0
		data.inside = true
		data.nearestPointIsVertex = false
		data.distance = math.max(0, math.abs(upDistance) - radius)
	else
		data.inside = false
		-- Is the nearest point a vertex?
		local lmdp = Vector.dotProduct_t(planeDistances[1].v, planeDistances[2].v)
		data.nearestPointIsVertex = mul_fx(lmdp, planeDistances[1].d) <= planeDistances[2].d
		if data.nearestPointIsVertex then
			-- order matters
			local b = planeDistances[1].v
			local m = planeDistances[2].v
			local t = nil
			if
			  (m == surface.outVector[1] and b == surface.inVector) or
			  (m == surface.outVector[2] and b == surface.outVector[1]) or
			  (m == surface.inVector and b == surface.outVector[2])
			  then
				t = someKindOfTransformation(lmdp, planeDistances[1].d, planeDistances[2].d, b, m)
			else
				t = someKindOfTransformation(lmdp, planeDistances[2].d, planeDistances[1].d, m, b)
			end
			edgeDistSq = t[1] * t[1] + t[2] * t[2] + t[3] * t[3]
			data.dist2d = math.sqrt(edgeDistSq)
			if edgeDistSq > 0 then
				distanceOffset = t
			end
		else
			edgeDistSq = planeDistances[1].d
			data.dist2d = edgeDistSq
			edgeDistSq = edgeDistSq * edgeDistSq
			distanceOffset = Vector.multiply(planeDistances[1].v, planeDistances[1].d / 0x1000)
		end
		
		data.distance = math.max(0, math.sqrt(edgeDistSq + upDistance * upDistance) - radius)
	end
	if data.distance == nil then error("nil distance to triangle!") end
	
	if distanceOffset ~= nil then
		data.distanceVector = Vector.subtract(data.distanceVector, distanceOffset)
	end
	if data.dist2d > radius or planeDistances[1].d >= radius or inDistance < -radius then
		data.pushOutBy = -1
	else
		data.pushOutBy = math.sqrt(radius * radius - edgeDistSq) - upDistance
	end
	
	data.interacting = true -- NOT the same thing as getting pushed
	if data.pushOutBy < 0 or radius - upDistance >= 0x1e001 then
		data.interacting = false
	elseif data.isBehind then
		if previousPos == nil then
			data.interacting = false
		elseif data.inside then
			if data.wasBehind == true and data.wasInside ~= true then
				data.interacting = false
			end
		else
			local o = 0
			if planeDistances[1].v == surface.inVector then
				o = surface.triangleSize
			end
			if Vector.dotProduct_t(previousPos, planeDistances[1].v) > o then
				data.interacting = false
			end	
		end
	end
	
	if data.wasBehind and previousPos ~= nil and Vector.dotProduct_t(previousPos, surface.surfaceNormal) < -0xa000 then
		data.wasFarBehind = true
	end
	
	if data.interacting then
		data.touchSlopedEdge = false
		if not data.inside and not data.nearestPointIsVertex and 0x424 >= planeDistances[1].v[2] and planeDistances[1].v[2] >= -0x424 then
			data.touchSlopedEdge = true
		end
	
		-- Will it push?
		data.push = true
		if toucher.previousPos ~= nil then
			local posDelta = Vector.subtract(toucher.pos, toucher.previousPos)
			local outwardMovement = Vector.dotProduct_t(posDelta, surface.surfaceNormal)
			-- 820 rule
			if outwardMovement > 819 then
				data.push = false
				data.outwardMovement = outwardMovement
			end
			
			-- Starting behind
			if data.wasBehind and (toucher.flags & 0x3b ~= 0 or data.wasFarBehind) then
				data.push = false
			end
		end
	end
	
	return data
end
local function getTouchDataForSurface(toucher, surface)
	local data = {}
	-- 1) Can we interact with this surface?
	-- Idk what these all represent.
	local st = surface.surfaceType
	if toucher.flags & 0x10 ~= 0 and st & 0xa000 ~= 0 then
		return { canTouch = false }
	end
	local unknown1 = st & 0x2010 == 0
	local unknown2 = toucher.flags & 4 == 0 or st & 0x2000 == 0
	local unknown3 = toucher.flags & 1 == 0 or st & 0x10 == 0
	if not (unknown1 or (unknown2 and unknown3)) then
		return { canTouch = false }
	end
	data.canTouch = true
	-- 2) How far away from the surface are we?
	local dd = getSurfaceDistanceData(toucher, surface)
	data.touching = dd.interacting
	data.pushOutDistance = dd.pushOutBy
	data.distance = dd.distance
	data.behind = dd.isBehind
	data.centerToTriangle = dd.distanceVector
	data.wasBehind = dd.wasBehind
	data.isInside = dd.inside
	data.push = dd.push
	data.outwardMovement = dd.outwardMovement
	data.dist2d = dd.dist2d
	-- wasInside

	if data.distance == nil then error("nil distance to triangle!") end
	return data
end
local function getCollisionDataForRacer(toucher)
	local nearby = getNearbyTriangles(toucher.pos, (mkdsiConfig.increaseRenderDistance and 3) or nil)
	if #nearby == 0 then
		return { all = {}, touched = {}, totalPush = Vector.zero() }
	end

	local data = {}
	local touchList = {}
	local nearestWall = nil
	local nearestFloor = nil
	local maxPushOut = nil
	local lowestTriangle = nil
	local touchedEdgeWall = false
	local touchedFloor = false
	local skipEdgeWalls = false
	local skipFloorVerticals = false

	local totalFloor = { min = Vector.zero(), max = Vector.zero() }
	local totalWall = { min = Vector.zero(), max = Vector.zero() }
	local totalEdge = { min = Vector.zero(), max = Vector.zero() }
	for i = 1, #nearby do
		local touch = getTouchDataForSurface(toucher, nearby[i])
		if touch.canTouch == true then
			local triangle = nearby[i]
			local thisData  = {
				triangle = triangle,
				touch = touch,
			}
			data[#data + 1] = thisData
			if touch.touching then
				touchList[#touchList + 1] = thisData
			end

			if touch.push then
				if triangle.isFloor and (maxPushOut == nil or touch.pushOutDistance > data[maxPushOut].touch.pushOutDistance) then
					maxPushOut = #data
				end
				if lowestTriangle == nil or touch.centerToTriangle[2] < lowestTriangle.touch.centerToTriangle[2] then
					lowestTriangle = thisData
				end
				touchedEdgeWall = touchedEdgeWall or triangle.collisionType == EDGE_WALL
				touchedFloor = touchedFloor or triangle.isFloor

				local pushDistance = math.floor(touch.pushOutDistance)
				local pushVector = Vector.multiply_t(triangle.surfaceNormal, pushDistance)
				if triangle.isFloor then
					updateMinMax(totalFloor, pushVector)
				elseif triangle.collisionType == EDGE_WALL then
					updateMinMax(totalEdge, pushVector)
				elseif triangle.isWall then
					updateMinMax(totalWall, pushVector)
				end
			end
			
			-- find nearest wall/floor
			if triangle.isWall and not touch.push and (nearestWall == nil or touch.distance < data[nearestWall].touch.distance) then
				nearestWall = #data
			end
			if triangle.isFloor and not touch.push and (nearestFloor == nil or touch.distance < data[nearestFloor].touch.distance) then
				nearestFloor = #data
			end
		end
	end
	
	if touchedEdgeWall and touchedFloor then
		local v = lowestTriangle.touch.centerToTriangle
		if v[1] * v[1] + v[3] * v[3] <= v[2] * v[2] then
			-- Not allowed to touch edge walls.
			skipEdgeWalls = true
			for i = 1, #touchList do
				if touchList[i].triangle.collisionType == EDGE_WALL then
					touchList[i].touch.skipByEdge = true
				end
			end
		else
			-- Not allowed to fully touch floors.
			skipFloorVerticals = true
			for i = 1, #touchList do
				if touchList[i].triangle.isFloor then
					touchList[i].touch.skipByEdge = true
				end
			end
		end
	end
	if maxPushOut ~= nil and skipFloorVerticals == false then
		data[maxPushOut].controlsSlope = true
	end

	if not skipEdgeWalls then
		updateMinMax(totalWall, totalEdge.min)
		updateMinMax(totalWall, totalEdge.max)
	end
	if skipFloorVerticals then
		totalFloor[2] = 0
	end
	updateMinMax(totalFloor, totalWall.min)
	updateMinMax(totalFloor, totalWall.max)
	local totalPush = Vector.add(totalFloor.min, totalFloor.max)
	
	return {
		all = data,
		touched = touchList,
		nearestFloor = nearestFloor,
		nearestWall = nearestWall,
		totalPush = totalPush,
	}
end


local function getCourseCollisionData()
	someCourseData = memory.read_bytes_as_array(Memory.addrs.collisionData + 1, 0x38 - 1)
	someCourseData[0] = memory.read_u8(Memory.addrs.collisionData)

	local dataPtr = get_u32(someCourseData, 8)
	local endData = get_u32(someCourseData, 12)
	local triangleData = memory.read_bytes_as_array(dataPtr + 1, endData - dataPtr)
	triangleData[0] = memory.read_u8(dataPtr)
	
	triangles = {}
	local triCount = (endData - dataPtr) / 0x10 - 1
	for i = 1, triCount do -- there is no triangle ID 0
		local offs = i * 0x10
		triangles[i] = {
			id = i,
			triangleSize = get_s32(triangleData, offs + 0),
			vertexId = get_s16(triangleData, offs + 4),
			surfaceNormalId = get_s16(triangleData, offs + 6),
			outVector1Id = get_s16(triangleData, offs + 8),
			outVector2Id = get_s16(triangleData, offs + 10),
			inVectorId = get_s16(triangleData, offs + 12),
			surfaceType = get_u16(triangleData, offs + 14),
		}
		triangles[i].collisionType = (triangles[i].surfaceType >> 8) & 0x1f
		triangles[i].unkType = (triangles[i].surfaceType >> 2) & 3
		triangles[i].props = (1 << triangles[i].collisionType) | (1 << (triangles[i].unkType + 0x1a))
		triangles[i].isWall = triangles[i].props & 0x214300 ~= 0
		triangles[i].isFloor = triangles[i].props & 0x1e34ef ~= 0
		triangles[i].isOob = triangles[i].props & 0xC00 ~= 0

		triangles[i].skip = triangles[i].isActuallyLine or (1 << triangles[i].collisionType) & skippableTypes ~= 0
	end
		
	local vectorsPtr = get_u32(someCourseData, 4)
	local vectorData = memory.read_bytes_as_array(vectorsPtr + 1, dataPtr - vectorsPtr + 0x10)
	vectorData[0] = memory.read_u8(vectorsPtr)
	local vectors = {}
	local vecCount = (dataPtr - vectorsPtr + 0x10) // 6
	for i = 0, vecCount - 1 do
		local offs = i * 6
		vectors[i] = get_pos_16(vectorData, offs)
	end
	
	local vertexesPtr = get_u32(someCourseData, 0)
	local vertexData = memory.read_bytes_as_array(vertexesPtr + 1, vectorsPtr - vertexesPtr) -- guess about length
	vertexData[0] = memory.read_u8(vertexesPtr)
	local vertexes = {}
	local vertCount = (vectorsPtr - vertexesPtr) / 12
	for i = 0, vertCount - 1 do
		local offs = i * 12
		vertexes[i] = get_pos(vertexData, offs)
	end
	
	for i = 1, #triangles do
		local tri = triangles[i]
		tri.surfaceNormal = vectors[tri.surfaceNormalId]
		tri.inVector = vectors[tri.inVectorId]
		tri.vertex = {}
		tri.slope = {}
		tri.vertex[1] = vertexes[tri.vertexId]
		tri.outVector = {}
		tri.outVector[1] = vectors[tri.outVector1Id]
		tri.outVector[2] = vectors[tri.outVector2Id]
		tri.outVector[3] = vectors[tri.inVectorId]
		tri.slope[1] = Vector.crossProduct_float(tri.surfaceNormal, tri.outVector[1])
		tri.slope[2] = Vector.crossProduct_float(tri.surfaceNormal, tri.outVector[2])
		tri.slope[3] = Vector.crossProduct_float(tri.surfaceNormal, tri.outVector[3])
		-- Both slope vectors should be unit vectors, since surfaceNormal and outVectors are.
		-- But one of them is pointed the wrong way
		tri.slope[1] = Vector.multiply(tri.slope[1], -1)
		local a = Vector.dotProduct_float(vectors[tri.inVectorId], tri.slope[1])
		local b = tri.triangleSize / a
		if a == 0 then
			-- This happens in rKB2.
			b = 0x1000 * 1000
			tri.ignore = true
		end
		local c = Vector.truncate(Vector.multiply(tri.slope[1], b))
		tri.vertex[3] = Vector.add(tri.vertex[1], c)
		a = Vector.dotProduct_float(vectors[tri.inVectorId], tri.slope[2])
		b = tri.triangleSize / a
		if a == 0 then
			-- This happens in rKB2.
			b = 0x1000 * 1000
			tri.ignore = true
		end
		c = Vector.truncate(Vector.multiply(tri.slope[2], b))
		tri.vertex[2] = Vector.add(tri.vertex[1], c)
	end
	
	local cmPtr = get_u32(someCourseData, 0xC)
	local cmSize = 0x28000 -- ???
	collisionMap = memory.read_bytes_as_array(cmPtr + 1, cmSize - 1)
	collisionMap[0] = memory.read_u8(cmPtr)

	return {
		triangles = triangles,
	}
end

_export = {
	getCourseCollisionData = getCourseCollisionData,
	getCollisionDataForRacer = getCollisionDataForRacer,
	getNearbyTriangles = getNearbyTriangles,
}