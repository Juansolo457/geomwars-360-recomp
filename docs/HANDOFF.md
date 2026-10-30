# Handoff: Geometry Wars: Retro Evolved 360 (2026-10-30)

Read [PLAN.md](PLAN.md) for the goals, decisions, milestones and the lessons from the sister
projects, and [FINDINGS.md](FINDINGS.md) for the package and executable facts. This file is the
state, the build/run detail and where things live. Update it at the end of every session; the
next model starts here, not from chat history.

## Where it stands
**Bootstrapped 2026-10-30, nothing built yet.** The repository has the Prey shape renamed, a new
STFS extractor (`tools/stfs.py`) that unpacked the Arcade package into `port/assets`, the
decrypted image and its facts (FINDINGS.md), a scaffold manifest with the setjmp/longjmp pair and
the VdSwap frame hook, and the host app setting the licence bit for the full game. **The first
codegen and build wait for the user's OK** (every build and run in this repo does, PLAN.md).

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

## Next steps (in order; each build or run needs the user's OK first)
1. **First codegen and build:** `tools/build.ps1` (codegen of a 1.1 MB image: seconds; the
   compile a few minutes). Then on `private/xex/default.bin`: `check_switch_tables.py`,
   `find_missed_functions.py`, `find_code_pointers.py` (round 2 wholesale, drop any
   "Unresolved"), `find_vcall_thunks.py`. Record the counts in FINDINGS.md "Translation facts".
2. **First run:** `tools/smoke.ps1 -Seconds 90 -CaptureEvery 3 -Autopilot tools/autopilot/boot.txt`.
   Expect a sign-in prompt (answer A), the title, the menu; check the log for the
   `license_mask 1` line and that no trial text shows. Fix the script's timings from the log.
3. **M2:** `menu.txt` into Evolved, stick moves added for the capture pass; every capture checked
   (grid, bloom, particles, HUD); game over and the high score surviving a restart
   (`XamUserWriteProfileSettings`); Retro the same way.
4. **60 Hz:** presents a second from the frame log in 10 s windows; the frame hook address
   confirmed from the generated code (`__imp__VdSwap`'s call site should be the only one).
5. **Live screens fail closed:** Leaderboards, Achievements, gamercard: what the stubs return
   and whether the menu copes.
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
  `port/out/build/win-amd64-relwithdebinfo/geomwars.exe`.
- **Every build, codegen and run needs the user's OK** (PLAN.md, decisions). The smoke window
  shows on the user's screen.

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
| `port/geomwars_manifest.toml` | function hints and hooks for the code generator: setjmp/longjmp, `GeomWarsFrameMark`; rounds to come |
| `port/src/` | host code: `geomwars_app.h` (Vulkan plugin by name, paths, controllers, licence bit), `crash_report`, `frame_timing`, `fpscr_guard` (unhooked), `autopilot`, `ui_pad`, `ui_style`, `audio_dump`, `timer_resolution`, `cpu_check` |
| `tools/patches/` | the SDK patch set `setup.ps1` applies (shared with the sister repos) and DOA4's Linux-only ones for `setup-linux.sh` |
| `tools/setup-linux.sh`, `build-linux.sh`, `build-deck.sh`, `tools/linux/`, `tools/steamdeck/` | the native Linux and Deck builds (Prey's/DOA4's, renamed, untested here) |
| `tools/autopilot/` | pad scripts for `smoke.ps1 -Autopilot`: `boot.txt` (title and menu, timings guessed), `menu.txt` (into Evolved) |
| `private/` | local only: decrypted image, strings and symbols (`xex/`), `analyze.py` (the one-off finder for the setjmp pair, mtfsf and the VdSwap site), captures, build and smoke logs |
| `docs/` | PLAN, HANDOFF (this), FINDINGS, SETUP |

## Known traps (from the sister projects; the full list is PLAN.md "Lessons applied")
- Jump tables on a 64 KB boundary and byte-indexed tables are misread by `bd833a2`; a
  halfword-index register bug too (DOA4). `check_switch_tables.py` after every codegen.
- A method right after a function's last branch has no `.pdata` entry and the analyser misses
  it (Prey's runs 1, 3, 4). `find_code_pointers.py` before the first run.
- `longjmp` through translated code without the manifest entries corrupts the host stack
  (libpng and libjpeg are in this image).
- Renderer options only as `--name=value`.
- A pad press in a runtime dialog needs `SetNavCursorVisible(true)` (in `ui_pad.cpp` already).
- `readback_resolve` defaults to `none`; decide per feature, log the chosen value.
- The rename from a sister repo must include `port/generated/rexglue.cmake` (tracked, BSD).
- `license_mask` 0 is the trial: the app sets 1; a run that shows trial text means the command
  line overrode it or the game reads another bit.
