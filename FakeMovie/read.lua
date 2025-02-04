dofile "json.lua"

local len = movie.length()
local inputs = {}
for i = 0, len - 1 do
	inputs[i] = movie.getinput(i)
end

local fs = io.open("fakemovieinputs.json", "w")
if fs == nil then error("could not open/create fakemovieinputs.json") end
fs:write(json.stringify(inputs))
io.close(fs)
