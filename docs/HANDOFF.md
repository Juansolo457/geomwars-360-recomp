# Handoff: Geometry Wars: Retro Evolved 360 (2026-10-30)

Read [PLAN.md](PLAN.md) for the goals, decisions, milestones and the lessons from the sister
projects, and [FINDINGS.md](FINDINGS.md) for the package and executable facts. This file is the
state, the build/run detail and where things live. Update it at the end of every session; the
next model starts here, not from chat history.

## Where it stands
**It boots and plays (2026-10-30, run 2): the Bizarre logo, "Select game mode", Evolved with the
grid, the ship, enemies, the bloom and the particle field, the pause menu, game over, at a
steady 60 fps on the Vulkan backend, no sign-in prompt, no trial text.** M0 and M1 of PLAN.md
are reached and **run 3 (`menu.txt`) played Evolved**: the sticks move and fire, kills score, a
bomb clears, lives are lost, the Achievements screen fails closed, 60 fps throughout; the user
watched and called it good. Left for M2: a high score surviving a restart, Retro, audio
listened to. Branch `first-build`, pull request #2; PR #1 (a HANDOFF paragraph, green) is still
open and its text is folded in below.

### Run 3 (2026-10-30, `menu.txt`, closed by the user at +108 s; log `port/logs/smoke-20261030-094609.log`, 35 captures in `private/captures/geomwars-evolved-20261030-094609/`)
- The script's stick legs work (+y is up); 3 s holds parked the ship on the arena wall, so
  `menu.txt` now holds each leg 1.2 s. Score 800 by +91 s, a bomb at the minute, two lives lost.
- The user took the pad: Achievements from the pause menu hit the `XamShowAchievementsUI` stub
  and the game went on (a new game started 5 s later). Facts in FINDINGS.md "Run 3 facts".
- All captures at 2560x1440 this time (the window was at display size; cause unverified).

### Run 2 (2026-10-30, `boot.txt` 90 s; log `port/logs/smoke-20261030-081716.log`, 29 captures in `private/captures/geomwars-boot2-20261030-081716/`)
- +3 s the Bizarre Creations logo; +6 s "Select game mode" (one START at 5 s got there, so the
  title's press-START screen takes one press); +9 s Evolved's spawn flash (START at 8 s); the
  script's third START at 11 s **paused** the game (Resume game / Help and options / Leaderboards
  / Achievements / Return to main menu) and its first A resumed it; the ship stood still, lost
  its three lives by +40 s, "Game over, Final score: 0, Continue" stayed up to the end.
- **60.0 fps in every 10 s window**, median 16.65 ms, 1% low 53-55 fps, 80-87% of presents on
  the 60 Hz vblank. One 238 ms stall at the game-over stats write (`XSessionWriteStats`,
  `XSessionEnd`, +40 s). 32 pipeline/shader creations, all in the first minute.
- No crash, no exception; the FPSCR guard hooks from run 1 did it. Log noise is listed in
  FINDINGS.md "Run 2 facts". The first capture (+3 s) came out at 2560x1440, the rest at the
  720p window: the window is created at the display's size and resized on the first frames
  (cosmetic; `capture_window.ps1` reads the client area).
- The scripts now carry run 2's timings: `boot.txt` is two STARTs; `menu.txt` adds a stick
  square-walk with the right stick firing and a bomb a minute, for the M2 capture pass.

### Run 1 (2026-10-30, `boot.txt` 90 s; log `port/logs/smoke-20261030-064125.log`)
- Vulkan on the RTX 4090, `license_mask 1` logged at start, the pad found; the first pipelines
  and render targets (a 320x8192 and a 640x4096 color target at EDRAM 0, then **1280x1024
  2xMSAA**: the game renders 720p with 2x MSAA), `XMPGetPlaybackController` polled.
- **Crash at +2 s: C000008F** on the audio worker (`crash-20261030-064127.txt`): the mixer
  `sub_820B33E8` under the render-driver callback `sub_82081578`. Fix: `GeomWarsGuardFpscr`
  hooked at the callback's entry and the four `mtfsf` (manifest), as DOA4 and Quake 4.

### Build and codegen rounds (2026-10-30)
1. Round 1, the scaffold manifest: one `UnresolvedCall` (0x82075438, a tail-branch leaf), added;
   `geomwars.exe` linked. Checks: 34 switches, 0 wrong; no vpkd3d128 hazard; 34 missed
   candidates, 26 code pointers (34 distinct), 0 vcall forwarders.
2. Round 2 (the 34): clean, finders at 0 (FINDINGS.md).
3. The five `GeomWarsGuardFpscr` hooks: codegen regenerated four translation units; the build
   is `private/build-4.log` (local).

### Done 2026-10-30 (bootstrap, no build)
- Repo from `../prey-360-recomp`'s tracked files, identifiers renamed (`prey` -> `geomwars`,
  `PreyApp` -> `GeomWarsApp`, `PREY_` -> `GEOMWARS_`), `port/generated/rexglue.cmake` included.
- `tools/stfs.py`: LIVE/PIRS/CON container reader (file table, hash chains, male/female table
  copies); `tools/extract.ps1 -Package`. Verified on the package: 42 files, `default.xex`
  SHA-256 `33ae2199...ff45`, `xexinfo.py` reads it (title 584107ED, v0.0.1.1, XDK 2135).
- `xexdump` (the Quake 4 tree's) made `private/xex/default.bin` (1,179,648 bytes), the sections
  and the 144 import names. `tools/xex_basic_decrypt.py` can't (LZX). `tools/xeximports.py`
  printed 0 imports for this XEX (its import-table walk doesn't fit this 2005 layout: a fix for
  later; the symbol list from xexdump served instead).
- FINDINGS.md: setjmp 0x82099830 / longjmp 0x82099600 (pattern from Prey's pair, one hit each),
  the VdSwap `bl` at 0x82032A1C (manifest hook `GeomWarsFrameMark`), four `mtfsf`, the four
  stub-only Live imports, the trial strings.
- `port/src/geomwars_app.h`: sets `license_mask` to 1 when it is still 0 (the SDK's default is
  the trial); `--license_mask=0` keeps the trial for testing.
- `tools/find_vcall_thunks.py` `.text` range set to this image's (0x82020000, 0xC2A34);
  `build.ps1`/`build-linux.sh` check the new SHA; `.gitignore`/`audit_repo.py` know `.tga`,
  `.dat`, `.xml` as this game's files.
- The SDK install stamp `geomwars-sdk-tree` written beside the sisters' in the shared install
  (tree `12884d9`), so `setup.ps1` sees it as done on this PC.

Repository: https://github.com/Juansolo457/geomwars-360-recomp, **public**, created 2026-10-30
(wiki and projects off, branches deleted on merge, topics xbox-360, recompilation, vulkan,
steam-deck, rexglue, xbla), the bootstrap commit on `master`. Branch protection read back from
the API after the push: `audit` required and strict, conversation resolution on, admins
included, force pushes and deletion off. CodeRabbit: the GitHub App covers the account; it
reviewed PR #1 (a summary, no threads). Pull requests are merged by the user, with a merge
commit (CONTRIBUTING.md).

### RECLINED R0 (branch `reclined-r0` off `first-build`)
Static half: FINDINGS.md "Game variables" (`tools/find_refs.py`). Memory scan: FINDINGS.md
"Game variables, memory scan" (run 4). `--geomwars_memscan=<dir>` (port/src/memscan.h) writes
snapshots, `tools/memscan.py` searches them (`list`, `values`, `search`, `trend`, `dump`), and
`tools/autopilot/memscan.txt` is the script. Confirmed: score, live and stored high score,
lives, bombs, the game-state word, and likely the multiplier. **Still open, and the next run
(needs the user's OK):** the ship's x,y with the stick legs at 0.7 deflection
(`memscan.txt` now; pass the cvar as `'-Extra:--geomwars_memscan=<abs dir>'`, because pwsh
reads a bare `--` value as a flag), then the enemy table. R1 (the play loop) starts after.

## Next steps (in order; each build or run needs the user's OK first)
1. **M2, the rest:** (done) the Evolved capture pass, run 3. Next: Retro (the second entry on
   "Select game mode": a DOWN before the START), and a capture-by-capture comparison against
   console footage (grid warp, bloom, particles, the HUD font) with the 1.2 s-leg `menu.txt`.
2. **High score persistence:** run 4 (the memory scan) beat the 10,000 seed with the script
   (15,450 at 108 s) but was stopped before game over and logged no profile write. Next: a run
   that beats the seed and reaches game over, then a second run with
   the same user directory (`-FreshProfile` off): does "Highscore" show the new value, and did
   the first run log `XamUserWriteProfileSettings`?
3. **Audio:** `--geomwars_audio_dump` + `tools/audio_report.py` for levels, clipping and
   submit-rate gaps; the user listens.
4. **Live screens fail closed:** Achievements does (run 3). Leaderboards from the pause menu
   (DOWN, DOWN, A) still to try, and the main menu's gamercard/leaderboard entries.
5. **Resolution and the window:** why run 3's window was 2560x1440 (the `--resolution 720p`
   request, or the user maximising it); 1440p and 4K runs for M3; the 238 ms game-over stall
   if it shows in play.
6. `tools/xeximports.py` fixed for this XEX's import table (or dropped in favour of xexdump's
   symbol list).
7. Linux (M4) after the Windows work is merged: Prey's/DOA4's `tools/setup-linux.sh`,
   `build-deck.sh`, `tools/steamdeck/` are in the tree, renamed and untested here.

## How it is built and run
```
pwsh -NoProfile -File tools/setup.ps1                     # once: toolchain + Vulkan-only SDK (~1 h)
pwsh -NoProfile -File tools/extract.ps1 -Package 'D:\x360-recomps\geomwars-retro-evolved\...\584107ED\000D0000\<package>'
pwsh -NoProfile -File tools/build.ps1 [-Jobs 12]          # codegen when needed, then compile
pwsh -NoProfile -File tools/smoke.ps1 -Seconds 60         # boot check; its window shows on the user's screen
pwsh -NoProfile -File tools/smoke.ps1 -Seconds 90 -CaptureEvery 3 -Autopilot tools/autopilot/boot.txt
pwsh -NoProfile -File tools/launch.ps1 -Windowed          # a window on the user's screen
```
- **On this PC** `.tools/` is a junction to `../n3-360-recomp/reference/N3-Recomp/.tools` (LLVM
  20.1.8, CMake 3.31.8, Ninja 1.13.1) and `third_party/rexglue-sdk-bd833a2` is a junction to
  `../quake4-360-recomp/third_party/rexglue-sdk-bd833a2`: ReXGlue `bd833a2` with GRAW's patch
  set, Quake 4's and LOTR's `vexptefp-underflow` (tree `12884d9`), built Vulkan-only.
  `tools/setup.ps1` checks the tree and the install stamp `geomwars-sdk-tree`. BFBC's
  `vulkan-depth-stencil-bit` patch lives in BFBC's own SDK copy, not in this tree; take it if
  stencil-tested draws vanish here. Anyone else runs `setup.ps1` and gets their own copy.
- `build.ps1` enters a VS 2022 DevShell, checks the XEX hash, runs `geomwars_codegen`,
  reconfigures once on the first run, then builds
  `port/out/build/win-amd64-relwithdebinfo/geomwars.exe`. A manifest change regenerates only
  the translation units it touches (the hooks: four of fourteen).
- **Every build, codegen and run needs the user's OK** (PLAN.md, decisions). The smoke window
  shows on the user's screen. `smoke.ps1` runs windowed at 720p with its own user and cache
  directories (`port/user-smoke`, `port/cache-smoke`).

## Analysis tools (all read-only on the game's files)
| | |
|---|---|
| `tools/stfs.py <package> list \| extract <dir>` | the Arcade container; `tools/extract.ps1` wraps it |
| `tools/xexinfo.py <xex>` | XEX2 headers: title, build time, entry, image size, encryption, XDK libraries |
| `..\quake4-definitive\build\xexdump\xexdump.exe <xex> private\xex\default` | the decrypted image (`default.bin`), sections and the import names (this XEX is LZX: the only way here) |
| `tools/check_switch_tables.py <image.bin> port/generated/default [--toml out.toml]` | replays every generated `switch` against the image; rerun after every codegen |
| `tools/find_missed_functions.py <image.bin> port/generated/default` | function entries the analyser missed, as manifest lines |
| `tools/check_vector_aliasing.py port/generated/default` | the vpkd3d128 hazard; `build.ps1` runs it |
| `tools/find_code_pointers.py <image.bin> port/generated/default port/geomwars_manifest.toml` | **run after every codegen**: code pointers in `.rdata`/`.data` that are unregistered and follow a function end |
| `tools/find_vcall_thunks.py <image.bin> port/generated/default private/xex/pdata_funcs.txt` | virtual-call forwarders with no function-table entry (this image's `.text` range) |
| `tools/rdoc_capture.ps1 -Times 20,23` | a scripted run under RenderDoc (the `GeomWarsFrameMark` hook at the game's VdSwap call) |
| `tools/rdoc_*.py` | run with `qrenderdoc --python` (RenderDoc 1.46 in `../graw360-recomp/private/tools/renderdoc/`) |
| `--geomwars_audio_dump <file>` + `tools/audio_report.py` | the audio output as raw float PCM with per-second levels, clipping, submit-rate gaps |

## Where things live
| | |
|---|---|
| `port/assets/` | the extracted package (ignored) |
| `port/geomwars_manifest.toml` | function hints and hooks for the code generator: setjmp/longjmp, rounds 1-2, `GeomWarsFrameMark`, the five `GeomWarsGuardFpscr` hooks |
| `port/src/` | host code: `geomwars_app.h` (Vulkan plugin by name, paths, controllers, licence bit), `crash_report`, `frame_timing`, `fpscr_guard` (hooked since run 1), `autopilot`, `ui_pad`, `ui_style`, `audio_dump`, `timer_resolution`, `cpu_check` |
| `tools/patches/` | the SDK patch set `setup.ps1` applies (shared with the sister repos) and DOA4's Linux-only ones for `setup-linux.sh` |
| `tools/setup-linux.sh`, `build-linux.sh`, `build-deck.sh`, `tools/linux/`, `tools/steamdeck/` | the native Linux and Deck builds (Prey's/DOA4's, renamed, untested here) |
| `tools/autopilot/` | pad scripts for `smoke.ps1 -Autopilot`: `boot.txt` (two STARTs into Evolved, timings from run 2), `menu.txt` (a played game of Evolved with stick moves, run 3) |
| `port/logs/` | smoke logs and crash reports (ignored): `smoke-20261030-064125.log` + `crash-20261030-064127.*` (run 1), `smoke-20261030-081716.log` (run 2), `smoke-20261030-094609.log` (run 3) |
| `private/` | local only: decrypted image, strings and symbols (`xex/`), `analyze.py` (the one-off finder for the setjmp pair, mtfsf and the VdSwap site), captures (`captures/geomwars-boot2-*`), build and smoke logs |
| `docs/` | PLAN, HANDOFF (this), FINDINGS, SETUP, RECLINED (the plan for a self-playing idle mode, 2026-10-30, nothing built) |

## Known traps (from the sister projects; the full list is PLAN.md "Lessons applied")
- Jump tables on a 64 KB boundary and byte-indexed tables are misread by `bd833a2`; a
  halfword-index register bug too (DOA4). `check_switch_tables.py` after every codegen.
- A method right after a function's last branch has no `.pdata` entry and the analyser misses
  it (Prey's runs 1, 3, 4). `find_code_pointers.py` before the first run.
- `longjmp` through translated code without the manifest entries corrupts the host stack
  (libpng and libjpeg are in this image).
- The audio worker's C000008F on an unseeded FP context: hit here in run 1, fixed by the five
  guard hooks; if a new FP exception shows on another thread, hook that thread's entry too.
- Renderer options only as `--name=value`.
- A pad press in a runtime dialog needs `SetNavCursorVisible(true)` (in `ui_pad.cpp` already).
- `readback_resolve` defaults to `none`; decide per feature, log the chosen value.
- The rename from a sister repo must include `port/generated/rexglue.cmake` (tracked, BSD).
- `license_mask` 0 is the trial: the app sets 1; a run that shows trial text means the command
  line overrode it or the game reads another bit.
- A third START in the autopilot pauses the game; the pause menu's A is "Resume game".
