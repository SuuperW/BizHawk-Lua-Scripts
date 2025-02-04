MKDS Info is a Lua script that aims to be useful for creating tool-assisted speedruns.

You can run MKDS Info by running "MKDS Info Main.lua", or by running "build.py" with Python and then running the .lua it creates. Both should behave identically.
A pre-built single-file version can be found at https://tasvideos.org/UserFiles/ForUser/Suuper, although it is not updated very often.

This script shows a bunch of information in text form on the bottom screen, and some information about collisions on the top screen.

Use the "new window" button to see a 2D top-down view of your kart's hitbox and nearby collision surfaces. You can also optionally display nearby objects and checkpoints. Change the viewing angle with the < and > buttons for "perspective". Press < once for a 3D view from the camera. You can resize the window, and then click the black box to resize it to match the window. Clicking the box without resizing (or clicking it again after resizing) will move the camera around (meant to be used with the "freeze location" option).

Use the < and > buttons for "Watching" on the main window to switch between viewing information for your kart and the ghost's kart (or CPUs if there are any).

You can also use the copy from player button to copy the inputs (recorded by the game itself) for the current race, to the ghost. The Lua script will automatically rewind to sync the ghost (though this may fail; if it does, manually rewind until it does sync and modify an input in TAStudio there). It will also rewind if needed when you load a branch. Click the button again to stop auto rewinding/updating ghost inputs. This feature makes it so you don't need to finish the race and start a new one in order to get a new ghost.

Most of the information displayed by the Lua script is explained on the MKDS Game Resources page.
