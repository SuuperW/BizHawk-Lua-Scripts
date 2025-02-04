local function zero()
	return { 0, 0, 0 }
end
local function getMagnitude(vector)
	local x = vector[1] / 4096
	local y = vector[2] / 4096
	local z = vector[3] / 4096
	return math.sqrt(x * x + z * z + y * y)
end
local function get2dMagnitude(vector)
	local x = vector[1] / 4096
	local z = vector[3] / 4096
	return x * x + z * z
end
local function distanceSqBetween(p1, p2)
	local x = p2[1] - p1[1]
	local y = p2[2] - p1[2]
	local z = p2[3] - p1[3]
	return x * x + y * y + z * z
end


-- Functions may come in up to three variants:
-- _r: The output is rounded to the nearest subunit.
-- _t: The output is truncated.
-- _float: No rouding; may return values that MKDS cannot represent.
local function normalize_float(v)
	--if v == nil or type(v) == "number" or v[1] == nil then print(debug.traceback()) end
	local m = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3]) / 0x1000
	return {
		v[1] / m,
		v[2] / m,
		v[3] / m,
	}
end

--- @param v1 [integer, integer, integer]
--- @param v2 [integer, integer, integer]
local function dotProduct_float(v1, v2)
	-- truncate, fixed point 20.12
	local a = v1[1] * v2[1] + v1[2] * v2[2] + v1[3] * v2[3]
	return a / 0x1000
end
--- @param v1 [integer, integer, integer]
--- @param v2 [integer, integer, integer]
local function dotProduct_t(v1, v2)
	-- truncate, fixed point 20.12
	local a = v1[1] * v2[1] + v1[2] * v2[2] + v1[3] * v2[3]
	return a // 0x1000 -- bitwise shifts are logical
end
--- @param v1 [integer, integer, integer]
--- @param v2 [integer, integer, integer]
local function dotProduct_r(v1, v2)
	-- round, fixed point 20.12
	local a = v1[1] * v2[1] + v1[2] * v2[2] + v1[3] * v2[3] + 0x800
	return a // 0x1000 -- bitwise shifts are logical
end

--- @param v1 [integer, integer, integer]
--- @param v2 [integer, integer, integer]
--- @return [number, number, number]
local function crossProduct_float(v1, v2)
	return {
		(v1[2] * v2[3] - v1[3] * v2[2]) / 0x1000,
		(v1[3] * v2[1] - v1[1] * v2[3]) / 0x1000,
		(v1[1] * v2[2] - v1[2] * v2[1]) / 0x1000,
	}
end
-- This one is special? It doesn't handle values as fixed-point like other ones do.
--- @param v [integer, integer, integer]
--- @param s number
--- @return [number, number, number]
local function multiply(v, s)
	--if v == nil or v[1] == nil then print(debug.traceback()) end
	return {
		v[1] * s,
		v[2] * s,
		v[3] * s,
	}
end
--- @param v [integer, integer, integer]
--- @param s integer
--- @return [integer, integer, integer]
local function multiply_r(v, s)
	return {
		math.floor(v[1] * s / 0x1000 + 0.5),
		math.floor(v[2] * s / 0x1000 + 0.5),
		math.floor(v[3] * s / 0x1000 + 0.5),
	}
end

--- @param v1 [integer, integer, integer]
--- @param v2 [integer, integer, integer]
--- @return [integer, integer, integer]
local function add(v1, v2)
	return {
		v1[1] + v2[1],
		v1[2] + v2[2],
		v1[3] + v2[3],
	}
end
--- @param v1 [integer, integer, integer]
--- @param v2 [integer, integer, integer]
--- @return [integer, integer, integer]
local function subtract(v1, v2)
	--if v1 == nil or v1[1] == nil or v2[1] == nil then print(debug.traceback()) end
	return {
		v1[1] - v2[1],
		v1[2] - v2[2],
		v1[3] - v2[3],
	}
end
--- @param v [number, number, number]
--- @return [integer, integer, integer]
local function truncate(v)
	return {
		math.floor(v[1]),
		math.floor(v[2]),
		math.floor(v[3]),
	}
end

--- @param v1 [number, number, number]
--- @param v2 [number, number, number]
local function equals(v1, v2)
	if v1[1] == v2[1] and v1[2] == v2[2] and v1[3] == v2[3] then
		return true
	end
end
--- @param v1 [number, number, number]
--- @param v2 [number, number, number]
local function equals_ignoreSign(v1, v2)
	if v1[1] == v2[1] and v1[2] == v2[2] and v1[3] == v2[3] then
		return true
	end
	v1 = multiply(v1, -1)
	return v1[1] == v2[1] and v1[2] == v2[2] and v1[3] == v2[3]
end
--- @param v [integer, integer, integer]
--- @return [integer, integer, integer]
local function copy(v)
	return { v[1], v[2], v[3] }
end

--- @param v1 [integer, integer, integer]
--- @param v2 [integer, integer, integer]
--- @return [integer, integer, integer]
local function interpolate(v1, v2, perc)
	return {
		v1[1] + perc * (v2[1] - v1[1]),
		v1[2] + perc * (v2[2] - v1[2]),
		v1[3] + perc * (v2[3] - v1[3]),
	}
end

_export = {
	zero = zero,
	getMagnitude = getMagnitude,
	get2dMagnitude = get2dMagnitude,
	distanceSqBetween = distanceSqBetween,
	normalize_float = normalize_float,
	dotProduct_float = dotProduct_float,
	dotProduct_t = dotProduct_t,
	dotProduct_r = dotProduct_r,
	crossProduct_float = crossProduct_float,
	multiply = multiply,
	multiply_r = multiply_r,
	add = add,
	subtract = subtract,
	truncate = truncate,
	equals = equals,
	equals_ignoreSign = equals_ignoreSign,
	copy = copy,
	interpolate = interpolate,
}
