-- Display the touch inputs on the bottom screen while playing a movie.
-- Only works while playing a movie.
-- Only works with default screen layout.

local function drawTouch(x, y, color)
	gui.use_surface("emu")
	y = y + 192
	gui.drawLine(0, y, 255, y, color)
	gui.drawLine(x, 192, x, 192+191, color)
end

while true do
	local frame = emu.framecount()
	local last = movie.getinput(frame - 2)
	local now = movie.getinput(frame - 1)
	local didDraw = false
	if last["Touch"] == true then
		drawTouch(last["Touch X"], last["Touch Y"], 0xffff0000)
		didDraw = true
	end
	if now["Touch"] == true then
		drawTouch(now["Touch X"], now["Touch Y"], 0xff00ff00)
		didDraw = true
	end
	
	-- BizHawk bug: If we don't draw anything then it won't clear what was drawn last frame.
	-- We also cannot use the clear function because other scripts might have drawn something. So we draw a transparent pixel.
	-- BizHawk bug?: A fully transparent draw is ignored. Draw outside visible region instead.
	if not didDraw then
		gui.drawPixel(-999, 0, 0xff000000)
	end
	
	emu.frameadvance()
end