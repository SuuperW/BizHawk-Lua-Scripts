This Lua was created to work around BizHawk's senseless restriction on movies' render settings, and to allow playing movies with hi-res 3D rendering.

To use it:
1) Open the movie you want to play and then run read.lua.
2) Pause and restart the core.
3) Set whatever settings you want (and restart the core if needed).
4) Run play.lua, then let the emulator run. It should apply the inputs from the movie.

Each time you run read.lua it will write the inputs to a file (fakemovieinputs.json), overwriting the file if it already exists. This file will then be read by play.lua.
