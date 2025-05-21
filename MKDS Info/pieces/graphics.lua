local Vector = _imports.Vector
local Objects = _imports.Objects
local KCL = _imports.KCL

local function fixLine(x1, y1, x2, y2)
	-- Avoid drawing over the bottom screen
	if y1 > 1 and y2 > 1 then
		return nil
	elseif y1 > 1 then
		local cut = (y1 - 1) / (y1 - y2)
		y1 = 1
		x1 = x2 + ((x1 - x2) * (1 - cut))
		if y2 < -1 then
			-- very high zooms get weird
			cut = (-1 - y2) / (y1 - y2)
			y2 = -1
			x2 = x1 + ((x2 - x1) * (1 - cut))
		end
	elseif y2 > 1 then
		local cut = (y2 - 1) / (y2 - y1)
		y2 = 1
		x2 = x1 + ((x2 - x1) * (1 - cut))
		if y1 < -1 then
			-- very high zooms get weird
			cut = (-1 - y1) / (y2 - y1)
			y1 = -1
			x1 = x2 + ((x1 - x2) * (1 - cut))
		end
	end
	-- If we cut out the other sides, that would lead to polygons not drawing correctly.
	-- Because if we zoom in, all lines would be fully outside the bounds and so get cut out.
	return { x1, y1, x2, y2 }
end

local function scaleAtDistance(point, size, camera)
	if camera.orthographic then
		size = size / camera.scale
		return size - 0.5 -- BizHawk dumb?
	else
		local v = Vector.subtract(point, camera.location)
		size = size / Vector.getMagnitude(v)
		return size / camera.fovW * camera.w
	end
end
local function point3Dto2D(vector, camera)
	local v = Vector.subtract(vector, camera.location)
	local mat = camera.rotationMatrix
	local rotated = {
		(v[1] * mat[1][1] + v[2] * mat[1][2] + v[3] * mat[1][3]) / 0x1000,
		(v[1] * mat[2][1] + v[2] * mat[2][2] + v[3] * mat[2][3]) / 0x1000,
		(v[1] * mat[3][1] + v[2] * mat[3][2] + v[3] * mat[3][3]) / 0x1000,
	}
	if camera.orthographic then
		return {
			rotated[1] / camera.scale / camera.w,
			-rotated[2] / camera.scale / camera.h,
		}
	else
		-- Perspective
		if rotated[3] < 0x1000 then
			return { 0xffffff, 0xffffff } -- ?
		end
		local scaledByDistance = Vector.multiply(rotated, 0x1000 / rotated[3])
		return {
			scaledByDistance[1] / camera.fovW,
			-scaledByDistance[2] / camera.fovH,
		}
	end
end
local function line3Dto2D(v1, v2, camera)
	-- Must have a line transformation, because:
	-- Assume you have a triangle where two vertexes are in front of camera, one to the left and one to the right.
	-- The other vertex is far behind the camera, directly behind.
	-- This triangle should appear, in 2D to have four points. The line from v1 to vBehind should diverge from the line from v2 to vBehind.
	v1 = Vector.subtract(v1, camera.location)
	v2 = Vector.subtract(v2, camera.location)
	local mat = camera.rotationMatrix
	v1 = {
		(v1[1] * mat[1][1] + v1[2] * mat[1][2] + v1[3] * mat[1][3]) / 0x1000,
		(v1[1] * mat[2][1] + v1[2] * mat[2][2] + v1[3] * mat[2][3]) / 0x1000,
		(v1[1] * mat[3][1] + v1[2] * mat[3][2] + v1[3] * mat[3][3]) / 0x1000,
	}
	v2 = {
		(v2[1] * mat[1][1] + v2[2] * mat[1][2] + v2[3] * mat[1][3]) / 0x1000,
		(v2[1] * mat[2][1] + v2[2] * mat[2][2] + v2[3] * mat[2][3]) / 0x1000,
		(v2[1] * mat[3][1] + v2[2] * mat[3][2] + v2[3] * mat[3][3]) / 0x1000,
	}
	if camera.orthographic then
		-- Orthographic
		return {
			{
				v1[1] / camera.scale / camera.w,
				-v1[2] / camera.scale / camera.h,
			},
			{
				v2[1] / camera.scale / camera.w,
				-v2[2] / camera.scale / camera.h,
			},
		}
	else		
		-- Perspective
		if v1[3] < 0x1000 and v2[3] < 0x1000 then
			return nil
		end
		local flip = false
		if v1[3] < 0x1000 then
			flip = true
			local temp = v1
			v1 = v2
			v2 = temp
		end
		local changed = nil
		if v2[3] < 0x1000 then
			local diff = Vector.subtract(v1, v2)
			local percent = (v1[3] - 0x1000) / diff[3]
			if percent > 1 then error("invalid math") end
			v2 = Vector.subtract(v1, Vector.multiply(diff, percent))
			if v2[3] > 0x1001 or v2[3] < 0xfff then
				print(v2)
				error("invalid math")
			end
			changed = 2
			if flip then changed = 1 end
		end
		if flip then
			local temp = v1
			v1 = v2
			v2 = temp
		end
		local s1 = Vector.multiply(v1, 0x1000 / v1[3])
		local s2 = Vector.multiply(v2, 0x1000 / v2[3])
		local p1 = {
			s1[1] / camera.fovW,
			-s1[2] / camera.fovH,
		}
		local p2 = {
			s2[1] / camera.fovW,
			-s2[2] / camera.fovH,
		}
		
		return { p1, p2, changed }
	end
end

local function solve(m, v)
	-- Solve the system of linear equations to find which 3D directions to move in
	-- horizontal is 1, 0, 0; vertical is 0, 1, 0
	local m1 = { m[1][1], m[1][2], m[1][3], v[1] }
	local m2 = { m[2][1], m[2][2], m[2][3], v[2] }
	local m3 = { m[3][1], m[3][2], m[3][3], v[3] }
	local t = nil
	if m1[1] == 0 then
		if m2[1] ~= 0 then t = m1; m1 = m2; m2 = t;
		else t = m1; m1 = m3; m3 = t; end
	end
	if m2[2] == 0 then
		t = m2; m2 = m3; m3 = t;
	end
	local elim = m2[1] / m1[1]
	m2 = { 0, m2[2] - m1[2]*elim, m2[3] - m1[3]*elim, m2[4] - m1[4]*elim }
	elim = m3[1] / m1[1]
	m3 = { 0, m3[2] - m1[2]*elim, m3[3] - m1[3]*elim, m3[4] - m1[4]*elim }
	elim = m3[2] / m2[2]
	m3 = { m3[1] - m2[1]*elim, 0, m3[3] - m2[3]*elim, m3[4] - m2[4]*elim }
	local z = m3[4] / m3[3]
	local y = (m2[4] - z*m2[3]) / m2[2]
	local x = (m1[4] - z*m1[3] - y*m1[2]) / m1[1]
	return { x, y, z }
end
local function getDirectionsFrom2d(camera)
	return {
		solve(camera.rotationMatrix, {0x1000, 0, 0}),
		solve(camera.rotationMatrix, {0, 0x1000, 0}),
	}
end

local PIXEL = 1 -- pixel, point, color
local CIRCLE = 2 -- circle, center, radius (2D), line, fill
local LINE = 3 -- line, point1, point2, color
local POLYGON = 4 -- polygon, verts, line, fill
local TEXT = 5 -- text, point, string

local HITBOX = 6 -- hitbox, object, hitboxType, color
local HITBOX_PAIR = 7 -- hitbox_pair, object, racer

local que = {}

local function addToDrawingQue(priority, data)
	priority = priority or 0
	if que[priority] == nil then
		que[priority] = {}
	end
	local pQue = que[priority]
	pQue[#pQue + 1] = data
end

local function lineFromVector(base, vector, scale, color, priority)
	local scaledVector = Vector.multiply(vector, scale / 0x1000)
	addToDrawingQue(priority, { LINE, base, Vector.add(base, scaledVector), color })
end

local function processQue(camera)
	-- Order of keys given by pairs is not guaranteed.
	-- We cannot use ipairs because we may not have a continuous range of priorities.
	local priorities = {}
	for k, _ in pairs(que) do
		priorities[#priorities + 1] = k
	end
	table.sort(priorities)
	
	local cw = camera.w
	local ch = camera.h
	local cx = camera.x
	local cy = camera.y
	local ops = {}
	local opid = 1

	local function makeCircle(point2D, radius2D, line, fill)
		if radius2D < cw * 3 then -- We skip drawing circles that are significantly larger than the screen...?
			-- Skip drawing cirlces if they are entirely outside the viewport.
			if point2D[2] * ch + radius2D >= -ch and point2D[2] * ch - radius2D <= ch then
				if point2D[1] * cw + radius2D >= -cw and point2D[1] * cw - radius2D <= cw then
					ops[opid] = {
						CIRCLE,
						point2D[1] * cw + cx - radius2D, point2D[2] * ch + cy - radius2D,
						radius2D * 2,
						line, fill,
					}
					opid = opid + 1
				end
			end
		end
	end

	local function makePolygon(verts, lineColor, fill)
		local edges = {}
		for j = 1, #verts do
			local e = nil
			if j ~= #verts then
				e = line3Dto2D(verts[j], verts[j + 1], camera)
			else
				e = line3Dto2D(verts[j], verts[1], camera)
			end
			if e ~= nil then
				edges[#edges + 1] = e
			end
		end
		if #edges ~= 0 then
			local points = {}
			for j = 1, #edges do
				points[#points + 1] = edges[j][1]
				if edges[j][3] ~= nil then
					points[#points + 1] = edges[j][2]
				end
			end
			local fp = {}
			for j = 1, #points do
				local nextId = (j % #points) + 1
				local line = fixLine(points[j][1], points[j][2], points[nextId][1], points[nextId][2])
				if line ~= nil then
					if #fp == 0 or line[1] ~= fp[#fp][1] or line[2] ~= fp[#fp][2] then
						fp[#fp + 1] = { line[1], line[2] }
					end
					if line[3] ~= fp[1][1] or line[4] ~= fp[1][2] then
						fp[#fp + 1] = { line[3], line[4] }
					end
				end
			end
			-- Transform points to screen pixels
			for i = 1, #fp do
				fp[i] = { math.floor(fp[i][1] * cw + cx + 0.5), math.floor(fp[i][2] * ch + cy + 0.5) }
			end
			
			if #fp ~= 0 then
				if #fp == 1 then
					ops[opid] = { PIXEL, fp[1][1], fp[1][2], lineColor }
				else
					ops[opid] = { POLYGON, fp, lineColor, fill }
				end
				opid = opid + 1
			end
		end
	end

	for i = 1, #priorities do
		for _, v in ipairs(que[priorities[i]]) do
			if v[1] == POLYGON then
				makePolygon(v[2], v[3], v[4])
			elseif v[1] == CIRCLE then
				local point = point3Dto2D(v[2], camera)
				makeCircle(point, v[3], v[4], v[5])
			elseif v[1] == HITBOX then
				local object = v[2]
				local hitboxType = v[3]
				local color = v[4]
				
				if camera.overlay == true and (color & 0xff000000) == 0xff000000 then
					color = color & 0x50ffffff
				end			
				local skipPolys = false
				if hitboxType == "spherical" or (hitboxType == "cylindrical" and Vector.equals(camera.rotationVector, {0,-0x1000,0})) then
					skipPolys = hitboxType == "cylindrical"
					local point2D = point3Dto2D(object.objPos, camera)
					local radius = scaleAtDistance(object.objPos, object.objRadius, camera)
					if radius > cw then
						makeCircle(point2D, radius, color, (((color >> 24) & 0xff ~= 0xff) and color) or nil)
						-- Small circles, so we can zoom in on racers to see the center
						local smallsize = 300
						radius = scaleAtDistance(object.objPos, smallsize, camera)
						makeCircle(point2D, radius, color, color & 0x3fffffff)
						makeCircle(point2D, radius / 10, color, color & 0x0fffffff)
						radius = scaleAtDistance(object.objPos, 1, camera)
						makeCircle(point2D, radius, color, color)
						if object.preMovementObjPos ~= nil then
							point2D = point3Dto2D(object.preMovementObjPos, camera)
							color = 0xff4060a0
							if camera.overlay == true then
								color = (color & 0xffffff) | 0x50000000
							end
							radius = scaleAtDistance(object.objPos, smallsize, camera)
							makeCircle(point2D, radius, color, color & 0x3fffffff)
							makeCircle(point2D, radius / 10, color, color & 0x0fffffff)
							radius = scaleAtDistance(object.objPos, 1, camera)
							makeCircle(point2D, radius, color, color)
						end
					else
						makeCircle(point2D, radius, color, color)
					end
				elseif hitboxType == "item" then
					local radius = scaleAtDistance(object.itemPos, object.itemRadius, camera)
					makeCircle(point3Dto2D(object.itemPos, camera), radius, color, color)
				-- elseif hitboxType == "cylindrical" then
					-- Drawn as either a circle (spherical above), or as polygons below
				end
				if not skipPolys and object.polygons ~= nil then
					if type(object.polygons) == "function" then
						object.polygons = object.polygons()
						if #object.polygons == 0 then error("Got no polygons.") end
					end
					local fill = color
					if object.cylinder2 == true or hitboxType == "cylindrical" then
						fill = nil
					end
					if hitboxType == "boxy" or object.typeId == 207 then
						color = 0xffffffff
					end
					-- We separate fill and outline draws because BizHawk's draw system has issues.
					if fill ~= nil then
						for j = 1, #object.polygons do
							makePolygon(object.polygons[j], nil, fill)
						end
					end
					for j = 1, #object.polygons do
						makePolygon(object.polygons[j], color, nil)
					end
				end
			elseif v[1] == LINE then
				local p = line3Dto2D(v[2], v[3], camera)
				if p ~= nil then
					-- Avoid drawing lines over the bottom screen
					local points = fixLine(p[1][1], p[1][2], p[2][1], p[2][2])
					if points ~= nil then
						ops[opid] = {
							LINE,
							points[1] * cw + cx, points[2] * ch + cy,
							points[3] * cw + cx, points[4] * ch + cy,
							v[4],
						}
						opid = opid + 1
					end
				end
			elseif v[1] == HITBOX_PAIR then
				local object = v[2]
				local racer = v[3]
				local oPos = object.objPos
				local rPos = racer.objPos
				if object.hitboxType == "item" then
					oPos = object.itemPos
					rPos = racer.itemPos
				end
				if camera.orthographic == true and object.hitboxType == "spherical" or object.hitboxType == "item" then
					local relative = Vector.subtract(oPos, rPos)
					local vDist = math.abs(Vector.dotProduct_float(relative, camera.rotationVector))
					local oradius = object.objRadius
					local rradius = racer.objRadius
					if object.hitboxType == "item" then
						oradius = object.itemRadius
						rradius =racer.itemRadius
					end
					local totalRadius = oradius + rradius
					if totalRadius > vDist then
						local touchHorizDist = math.sqrt(totalRadius * totalRadius - vDist * vDist)
						makeCircle(point3Dto2D(rPos, camera), scaleAtDistance(rPos, touchHorizDist * rradius / totalRadius, camera), 0xffffffff, nil)
						makeCircle(point3Dto2D(oPos, camera), scaleAtDistance(oPos, touchHorizDist * oradius / totalRadius, camera), 0xffffffff, nil)
					end
				elseif object.hitboxType == "boxy" then
					local racerPolys = Objects.getBoxyPolygons(
						racer.objPos,
						object.orientation,
						{ racer.objRadius, racer.objRadius, racer.objRadius }
					)
					for j = 1, #racerPolys do
						makePolygon(racerPolys[j], 0xffffffff, nil)
					end
			
				end
			elseif v[1] == PIXEL then
				local point = point3Dto2D(v[2], camera)
				if point[2] >= -1 and point[2] < 1 then
					if point[1] >= -1 and point[1] < 1 then
						ops[opid] = { PIXEL, point[1] * cw + cx, point[2] * ch + cy, v[3] }
						opid = opid + 1
					end
				end
			elseif v[1] == TEXT then
				-- Coordinates for TEXT are in pixels.
				if v[2][2] >= 0 and v[2][2] < ch+cy then
					if v[2][1] >= 0 and v[2][1] < cw+cx then
						ops[opid] = { TEXT, v[2][1], v[2][2], v[3] }
						opid = opid + 1
					end
				end
			end
		end
	end

	return ops
end

local function makeRacerHitboxes(allRacers, focusedRacer)
	local count = #allRacers
	local isTT = count <= 2
	-- Not the best TT detection. But, if we are in TT mode we want to only show for-triangle hitboxes!
	-- Outside of TT, non-player hitboxes will be drawn as objects instead.
	if not isTT then count = 0 end

	-- Primary hitbox circle is blue
	local color = 0xff0000ff
	local movementColor = 0xffffffff
	local p = -3
	for i = 0, count do
		local racer = allRacers[i]
		local pos = racer.itemPos
		local radius = racer.itemRadius
		local type = "item"
		if racer == focusedRacer or isTT then
			pos = racer.objPos
			radius = racer.objRadius
			type = "spherical"
		end
		addToDrawingQue(p, { HITBOX, racer, type, color })
		lineFromVector(pos, allRacers[i].movementDirection, radius, movementColor, 5)
		-- Others are a translucent red
		color = 0x48ff5080
		movementColor = 0xcccccccc
		p = -1
	end

	if not isTT and focusedRacer ~= allRacers[0] and focusedRacer ~= nil and focusedRacer.isRacer then
		local racer = focusedRacer
		addToDrawingQue(p, { HITBOX, racer, "spherical", color })
		lineFromVector(racer.objPos, racer.movementDirection, racer.objRadius, movementColor, 5)
	end
end	

local function drawTriangle(tri, d, racer, dotSize, viewport)
	if tri.skip then return end
	if viewport ~= nil and viewport.backfaceCulling == true then
		if viewport.orthographic then
			if Vector.dotProduct_float(tri.surfaceNormal, viewport.rotationVector) > 0 then return end
		else
			if Vector.dotProduct_float(
				tri.surfaceNormal,
				Vector.subtract(tri.vertex[1], viewport.location)
			) > 0 then return end
		end
	end 

	-- fill
	local touchData = d and d.touch
	if touchData == nil then
		touchData = { touching = false }
	end
	if touchData.touching then
		local color = 0x30ff8888
		if touchData.push then
			if d.controlsSlope then
				color = 0x4088ff88
				lineFromVector(racer.objPos, tri.surfaceNormal, racer.objRadius, 0xff00ff00, 5)
			elseif d.isWall then
				color = 0x20ffff22
			elseif touchData.skipByEdge then
				color = 0x30ffcc88
			else
				color = 0x50ffffff
			end
		else
			lineFromVector(racer.objPos, tri.surfaceNormal, racer.objRadius, 0xffff0000, 5)
		end
		addToDrawingQue(-5, { POLYGON, tri.vertex, 0, color })
	end

	-- lines and dots
	local color, priority = "white", 0
	if tri.isWall then
		if touchData.touching and touchData.push and not touchData.skipByEdge then
			color, priority = "yellow", 2
		else
			color, priority = "orange", 1
		end
	elseif tri.isOob then
		color = "red"
	end
	addToDrawingQue(priority, { POLYGON, tri.vertex, color, nil })
	if dotSize ~= nil then
		if dotSize == 1 then
			addToDrawingQue(9, { PIXEL, tri.vertex[1], 0xffff0000 })
			addToDrawingQue(9, { PIXEL, tri.vertex[2], 0xffff0000 })
			addToDrawingQue(9, { PIXEL, tri.vertex[3], 0xffff0000 })
		else
			addToDrawingQue(9, { CIRCLE, tri.vertex[1], dotSize, 0xffff0000, 0xffff0000 })
			addToDrawingQue(9, { CIRCLE, tri.vertex[2], dotSize, 0xffff0000, 0xffff0000 })
			addToDrawingQue(9, { CIRCLE, tri.vertex[3], dotSize, 0xffff0000, 0xffff0000 })
		end
	end

	-- surface normal vector, kinda bad visually
	--if and tri.surfaceNormal[2] ~= 0 and tri.surfaceNormal[2] ~= 4096 then
		--local center = Vector.add(Vector.add(tri.vertex[1], tri.vertex[2]), tri.vertex[3])
		--center = Vector.multiply(center, 1 / 3)
		--lineFromVector(center, tri.surfaceNormal, racer.objRadius, color, 4)
	--end
end
local function makeKclQue(viewport, focusObject, allTriangles, textonly)
	if allTriangles ~= nil and textonly ~= true then
		for i = 1, #allTriangles do
			drawTriangle(allTriangles[i], nil, focusObject, nil, viewport)
		end
	end

	local touchData = KCL.getCollisionDataForRacer({
		pos = focusObject.objPos,
		previousPos = focusObject.preMovementObjPos,
		radius = focusObject.objRadius,
		flags = 1, -- TODO: assume for now it is a racer
	})

	if textonly ~= true then
		local dotSize = 1
		if viewport.w > 128 then dotSize = 1.5 end
		for i = 1, #touchData.all do
			local d = touchData.all[i]
			if d.touch.canTouch then
				drawTriangle(d.triangle, d, focusObject, dotSize, viewport)
			end
		end
	end

	local y = 19
	if touchData.nearestWall ~= nil then
		local t = touchData.all[touchData.nearestWall].touch
		if t.isInside then
			addToDrawingQue(99, { TEXT, { 2, y }, string.format("closest wall: %i", t.distance) })
		else
			addToDrawingQue(99, { TEXT, { 2, y }, string.format("closest wall: %.2f", t.distance) })
		end
		y = y + 18
	end
	if touchData.nearestFloor ~= nil then
		local t = touchData.all[touchData.nearestFloor].touch
		if t.isInside then
			addToDrawingQue(99, { TEXT, { 2, y }, string.format("closest floor: %i", t.distance) })
		else
			addToDrawingQue(99, { TEXT, { 2, y }, string.format("closest floor: %.2f", t.distance) })
		end
		y = y + 18
	end
	
	y = y + 3
	for i = 1, #touchData.touched do
		local d = touchData.touched[i]
		local tri = d.triangle
		local stype = ""
		if tri.isWall then stype = stype .. "w" end
		if tri.isFloor then stype = stype .. "f" end
		if stype == "" then stype = tri.collisionType end
		local ps = ""
		if d.touch.push == false then
			if d.touch.wasBehind then
				ps = "n (behind)"
			else
				ps = string.format("n %.2f", d.touch.outwardMovement)
			end
		else
			local p = "p"
			if d.touch.skipByEdge then
				p = "edge"
			end
			if d.touch.isInside then
				ps = string.format("%s %i", p, d.touch.pushOutDistance)
			else
				ps = string.format("%s %.2f", p, d.touch.pushOutDistance)
			end
		end
		local str = string.format("%i: %s, %s", tri.id, stype, ps)
		addToDrawingQue(99, { TEXT, { 2, y }, str })
		
		y = y + 18
	end
end

local function _drawObjectCollision(racer, obj)
	if obj.skip == true then return end

	local objColor = 0xff40c0e0
	if obj.typeId == 106 then objColor = 0xffffff11 end
	addToDrawingQue(-4, { HITBOX, obj, obj.hitboxType, objColor })
	if obj.hitboxType == "spherical" or obj.hitboxType == "item" then
		-- White circles to indicate size of hitbox cross-section at the current elevation.
		if racer ~= nil then
			addToDrawingQue(-1, { HITBOX_PAIR, obj, racer })
		end
	elseif obj.hitboxType == "boxy" and racer ~= nil then
		addToDrawingQue(-2, { HITBOX_PAIR, obj, racer })
	end
end
local function makeObjectsQue(focusObject)
	if focusObject == nil then error("Attempted to draw objects with no focus.") end
	local nearby = Objects.getNearbyObjects(focusObject, mkdsiConfig.objectRenderDistance)
	local objects = nearby[1]
	local nearest = nearby[2]
	for i = 1, #objects do
		if objects[i] == nearest then
			_drawObjectCollision(focusObject, objects[i])
		else
			_drawObjectCollision(nil, objects[i])
		end
	end
	-- A focused racer will have a KCL hitbox drawn. Other things won't.
	if not focusObject.isRacer then
		_drawObjectCollision(nil, focusObject)
	end
end

local function makeCheckpointsQue(checkpoints, racer, package)
	local pos = racer and racer.basePos
	if pos == nil then pos = { 0, 0x100000, 0 } end
	local function elevate(p)
		return { p[1], pos[2], p[2] }
	end
	local function checkpointLine(c)
		local color = 0xff11ff11
		if c.isKey then color = 0xff1199ff end
		if c.isFinish then color = 0xffff2222 end
		addToDrawingQue(1, { LINE, elevate(c.point1), elevate(c.point2), color })
	end
	local function checkpointConnections(c1, c2)
		addToDrawingQue(1, { LINE, elevate(c1.point1), elevate(c2.point1), 0xff808080 })
		addToDrawingQue(1, { LINE, elevate(c1.point2), elevate(c2.point2), 0xff808080 })
	end


	for i = 0, checkpoints.count - 1 do
		checkpointLine(checkpoints[i])
		for j = 1, #checkpoints[i].nextChecks do
			checkpointConnections(checkpoints[checkpoints[i].nextChecks[j]], checkpoints[i])
		end
	end

	-- the racer position
	addToDrawingQue(1, { CIRCLE, pos, 10, 0xffffffff, nil })
	-- can we do crosshairs?
end

local function makePathsQue(paths, endFrame)
	for j = 1, #paths do
		local path = paths[j].path
		local color = paths[j].color
		local last = nil
		for i = endFrame - 750, endFrame do
			if path[i] ~= nil and last ~= nil then
				addToDrawingQue(3, { LINE, last, path[i], color })
			end
			last = path[i]
		end
	end
end

local function processPackage(camera, package)
	que = {}
	local thing
	if camera.racerId ~= -1 then
		thing = package.allRacers[camera.racerId]
	else
		thing = camera.obj
	end
	if thing ~= nil then
		Objects.getObjectDetails(thing)
	end
	if camera.active then
		if camera.drawKcl == true then
			if camera.racerId == nil then error("no racer id") end
			makeKclQue(camera, thing, (camera.renderAllTriangles and package.allTriangles) or nil)
		end
		if camera.drawObjects == true then
			makeObjectsQue(thing)
		end
		if camera.drawKcl == true or camera.drawObjects == true then
			makeRacerHitboxes(package.allRacers, thing)
		end
		if camera.drawCheckpoints == true then
			makeCheckpointsQue(package.checkpoints, thing, package)
		end
		if camera.drawPaths == true then
			makePathsQue(package.paths, package.frame)
		end
	elseif camera.isPrimary then
		-- We always show the text for nearest+touched triangles.
		makeKclQue(camera, thing, (camera.renderAllTriangles and package.allTriangles) or nil, true)
		if camera.drawRacers == true then
			makeRacerHitboxes(package.allRacers, thing)
		end
	end

	-- Hacky: Player hitbox is transparent on the main screen when in 3D view (.overlay == true)
	-- But if we are using renderHitboxesWhenFakeGhost, .overlay may be false.
	if camera.drawRacers == true then -- .drawRacers means renderHitboxesWhenFakeGhost is on and fake ghost exists.
		local temp = camera.overlay
		camera.overlay = true
		local que = processQue(camera)
		camera.overlay = temp
		return que
	else
		return processQue(camera)
	end
end
local function drawClient(camera, package)
	local operations = processPackage(camera, package)

	if (camera.overlay == false and camera.active == true) or (camera.isPrimary ~= true) then
		gui.drawRectangle(camera.x - camera.w, camera.y - camera.h, camera.w * 2, camera.h * 2, "black", "black")
	end
	for i = 1, #operations do
		local op = operations[i]
		if op[1] == POLYGON then
			gui.drawPolygon(op[2], 0, 0, op[3], op[4])
		elseif op[1] == CIRCLE then
			gui.drawEllipse(op[2], op[3], op[4], op[4], op[5], op[6])
		elseif op[1] == LINE then
			gui.drawLine(op[2], op[3], op[4], op[5], op[6])
		elseif op[1] == PIXEL then
			gui.drawPixel(op[2], op[3], op[4])
		elseif op[1] == TEXT then
			camera.drawText(op[2], op[3], op[4])
		end
	end
end
local function drawForms(camera, package)
	local operations = processPackage(camera, package)

	local b = camera.box
	if camera.overlay == false then
		forms.clear(b, 0xff000000)
	end
	for i = 1, #operations do
		local op = operations[i]
		if op[1] == POLYGON then
			forms.drawPolygon(b, op[2], 0, 0, op[3], op[4])
		elseif op[1] == CIRCLE then
			forms.drawEllipse(b, op[2], op[3], op[4], op[4], op[5], op[6])
		elseif op[1] == LINE then
			forms.drawLine(b, op[2], op[3], op[4], op[5], op[6])
		elseif op[1] == PIXEL then
			forms.drawPixel(b, op[2], op[3], op[4])
		elseif op[1] == TEXT then
			camera.drawText(op[2], op[3], op[4], 0xffffffff)
		end
	end
	forms.refresh(b)
end

local function setPerspective(camera, surfaceNormal)
	-- We will look in the direction opposite the surface normal.
	local p = Vector.multiply(surfaceNormal, -1)
	camera.rotationVector = p
	-- The Z co-ordinate is simply the distance in that direction.
	local mZ = { p[1], p[2], p[3] }
	-- The X co-ordinate should be independent of Y. So this vector is orthogonal to 0,1,0 and mZ.
	local mX = nil
	if surfaceNormal[1] ~= 0 or surfaceNormal[3] ~= 0 then
		mX = Vector.crossProduct_float(mZ, { 0, 0x1000, 0 })
		-- Might not be normalized. Normalize it.
		
		mX = Vector.multiply(mX, 1 / Vector.getMagnitude(mX))
	else
		mX = { 0x1000, 0, 0 }
	end
	mX = { mX[1], mX[2], mX[3] }
	local mY = Vector.crossProduct_float(mX, mZ)
	mY = { mY[1], mY[2], mY[3] }
	camera.rotationMatrix = { mX, mY, mZ }
end

_export = {
	drawClient = drawClient,
	drawForms = drawForms,
	setPerspective = setPerspective,
	getDirectionsFrom2d = getDirectionsFrom2d,
}
