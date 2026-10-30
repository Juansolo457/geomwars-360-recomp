// GEOMWARS 360 - snapshots of the guest's committed memory, for finding the game's variables
// (docs/RECLINED.md, R0). Off unless --geomwars_memscan=<dir> is given. Then, from the game's
// own frame hook, every --geomwars_memscan_every_ms (default 2000), up to
// --geomwars_memscan_limit snapshots (default 60), it writes <dir>/<seq>-<ms>/ holding
// chunks.idx ("<guest address hex> <size>" per line) and data.bin (the chunks back to back;
// 64 KB chunks that are all zero are left out). One log line per snapshot prints the new-game
// block at 0x820FFE80 (score, lives, bombs) as FINDINGS.md reads it, so a capture's HUD can be
// checked against it. tools/memscan.py reads the snapshots.
//
// Reads only, on the game thread that calls VdSwap (a snapshot stalls that frame; the frame log
// shows it). Guest addresses below 0xA0000000 by default (the virtual heaps and the image);
// --geomwars_memscan_all adds the physical views. Windows only (VirtualQuery over the arena);
// elsewhere it logs once and does nothing.
#pragma once

namespace geomwars::memscan {

// Called once per game frame from GeomWarsFrameMark (frame_timing.cpp). Cheap when off.
void OnFrame();

}  // namespace geomwars::memscan
