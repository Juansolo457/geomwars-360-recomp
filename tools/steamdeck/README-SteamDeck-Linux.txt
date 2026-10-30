GEOMWARS 360 recomp: native Linux build for the Steam Deck
======================================================

The game built for Linux: no Proton, no Wine. It draws with the renderer's Vulkan backend straight
on the Deck's GPU driver (RADV). Private test build: it holds programs made from your Xbox Live Arcade package, and
game/ holds your disc's data. Never share or upload it.

What's in this folder (GEOMWARS-360-SteamDeck/)
  geomwars-linux.sh         the launcher (point Steam at this): system info and the game's output
                        go to logs/
  geomwars + librexruntime.so, librexgpu-xenos.so   the program, Release build (the fastest)
  geomwars-relwithdebinfo + the *rd.so libraries    the same program with debug info, for crash
                        backtraces (GEOMWARS_DEBUG=1 in the launch options runs it)
  geomwars.toml             the Deck's settings (fullscreen, 720p, 16x AF)
  game/                 the disc's files
  user/                 your profile and saves (made on the first start)
  logs/                 made on the first start: system-<time>.txt, stdout-<time>.txt and the
                        game's own log
  VERSION.txt           which build this is

Setup (Desktop Mode)
  1. Steam > Games > "Add a Non-Steam Game to My Library" > Browse > set the file type to
     "All Files" > /home/deck/recomps/GEOMWARS-360-SteamDeck/geomwars-linux.sh > Add.
  2. In the library, right-click the new entry > Properties:
       - Compatibility: leave "Force the use of a specific Steam Play compatibility tool"
         UNTICKED. This is a Linux program; Proton can't run it.
       - Shortcut > LAUNCH OPTIONS: leave empty (or GEOMWARS_DEBUG=1 %command% for the debug build).
  3. Rename it (e.g. "Geometry Wars (Linux)") and go back to Game Mode.

What to expect
  - 720p, the console's resolution. resolution_scale in geomwars.toml raises it (2 = 1440p).
  - Shaders are built the first time each effect is seen (brief hitches on the first run); they
    are kept in user/cache, so judge smoothness on the second run.
  - The controller comes through Steam Input, as for any non-Steam game.

If it doesn't start: logs/system-<time>.txt says what the Deck has (glibc, libstdc++, the
libraries the program found) and logs/stdout-<time>.txt has the game's output.
