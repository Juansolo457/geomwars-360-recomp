# Findings: the package and the executable

Facts about the supported copy and its `default.xex`, with how each was found. Every address is
a virtual address in the decrypted image (base `0x82000000`) of the executable below. Nothing
about where the copy came from is recorded here.

## The package
- An **Xbox Live Arcade title**: one **LIVE** STFS container of 15,532,032 bytes, stored on the
  console under `584107ED\000D0000\` (title ID, content type `000D0000` = Arcade title). Its
  header names it "Geometry Wars Evolved"; 3,757 blocks, a "female" package (one copy of each
  hash table), top hash level 1. `tools/stfs.py <package> list` reads it; `tools/extract.ps1`
  unpacks it into `port/assets`.
- **42 files, 15 MB**, all in the root:
  - `default.xex`, the executable (450,560 bytes);
  - `GW1.xwb` (1.9 MB), `GW2.xwb` (4.1 MB), `GW2_Music.xwb` (8.5 MB): **XACT wave banks**, loaded
    by the game's own code (`WaveBank::Load()` in the image) and played through the XAudio render
    driver imports; Retro's and Evolved's sounds and Evolved's music;
  - `GeometryWars1.dat` (8,766 bytes) and `GeometryWars2.dat` (12,056 bytes): the game's data
    tables, named in the image as `GAME:\GeometryWars1.dat` / `2.dat` (Retro and Evolved);
  - the sprites as 64x64 32-bit **TGA** (16,428 bytes each): `player1`, `grunt`, `wanderer`,
    `weaver`, `spinner`, `tinyspinner`, `snake`, `mayfly`, `proton`, `repulsar`,
    `gravitywell0/1`, plus `spark.tga` and `retrobizarre.tga` (the Retro-mode Bizarre logo);
  - PNG icons for the dashboard: `game.png`, `marketplace.png`, one per enemy, and the seven
    rating boards (`RATING_ESRB.png`...);
  - `ArcadeInfo.xml` (UTF-16 big-endian): TitleInfo ID 1480656877 (= `0x584107ED`), name
    "Geometry Wars", `MaxCred` 200, one player.

## The executable
| | |
|---|---|
| File | `default.xex`, 450,560 bytes |
| SHA-256 | `33ae21996edb93478d5eef4f58ae0bec5f5411d3b6a7103a2141bd9f6154ff45` (`tools/build.ps1` checks it) |
| Title, version | `584107ED`, **0.0.1.1**, media `00000000`, disc 0/0 |
| Built | **2005-11-02 15:21 UTC** (three weeks before the console's launch); PE checksum `000FED3E` |
| XDK | **2.0.2135** (the launch XDK, DOA4's): XAPILIB, D3D9, D3DX9, XGRAPHC, XBOXKRNL, XNET, XAUD, LIBCPMT, XONLINE, XMP |
| Image | base `0x82000000`, size `0x120000` (1,179,648 bytes decrypted), entry `0x82029F60`, default stack 256 KB; AES-encrypted (retail key), **LZX** compression (`tools/xex_basic_decrypt.py` can't, it handles basic compression only; `xexdump` was used) |

Sections (`xexdump`, 2026-10-30):
| Section | Address | Size | |
|---|---|---|---|
| .rdata | `0x82000400` | `0x19AD4` | |
| .pdata | `0x8201A000` | `0x3720` | function table, **1,764 entries** |
| .text | `0x82020000` | `0xC2A34` | 780 KB of code; the import thunks at its end (`0x820E2134`..) |
| .data | `0x820F0000` | `0x17BB8` | |
| .XEXID | `0x82107C00` | `0x4` | |
| .idata | `0x82110000` | `0x2DE` | |
| .XBLD | `0x82120000` | `0xA0` | |
| .reloc | `0x82120200` | `0xE920` | |

### Imports (144)
From `xexdump`'s symbol list (`private/xex/default.symbols.txt`). Graphics: the full `Vd*` set
(`VdSwap`, `VdInitializeEngines`, `VdInitializeEDRAM`, `VdRetrainEDRAM`, `VdSetDisplayMode`,
`VdQueryVideoMode`...). Audio: `XAudioRegisterRenderDriverClient`,
`XAudioSubmitRenderDriverFrame`, `XAudioGetVoiceCategoryVolume` (the game's own mixer feeds the
render driver) and seventeen `XMA*` context calls (the wave banks are XMA). Input:
`XamInputGetState` only, no `XamInputGetKeystroke`: **no keyboard path in this game**. Live and
profile: `XamUserGetSigninState`, `XamUserGetXUID`, `XamShowSigninUI`,
`XamUserRead/WriteProfileSettings`, `XamUserCreateStatsEnumerator` (leaderboards),
`XamShowAchievementsUI`, `XamShowGamerCardUIForXUID`, `XamShowMarketplaceUI` (the trial's
"Unlock full game"), `XamContentGetLicenseMask` (trial or full), `XamSessionCreateHandle`,
`NetDll_XNetStartup`/`WSAStartup`, `XamLoaderLaunchTitle`/`TerminateTitle`. Files: `NtCreateFile`
and friends (no `XamContentCreate`: no save content package; scores and settings go through
profile settings). No fiber routines: no `[entrypoint.rexcrt]` needed.

Against the SDK (`bd833a2`): every import has an export-table entry. Four have only that, no
implementation (a logged stub): `XamUserCreateStatsEnumerator`, `XamShowAchievementsUI`,
`XamShowGamerCardUIForXUID`, `XamShowMarketplaceUI`. They are reached from the menus
(Leaderboards, Achievements, a gamercard, Unlock full game) and must fail closed there.

### Engine and middleware (from the decrypted image's strings, 2026-10-30)
- 3,434 printable strings of 6+ characters (`private/xex/strings.txt`). "Bizarre Creations",
  "Bizarre Creations Ltd", "Bizarre Biz"; "RETRO EVOLVED", "Geometry Wars Evolved".
- **Shaders compiled into the image**: "Microsoft (R) Xbox 360 Shader Compiler 2.0.2135.0" and
  D3DX's "#File created by Microsoft (R) D3DX library" (no run-time shader assembly: GRAW's
  jump-table class of bug is less likely here).
- **libpng**, **libjpeg** (JFIF/Adobe markers) and **zlib** version strings: the TGA/PNG sprites
  and icons are decoded in the game; libpng's and libjpeg's error exits `longjmp` (the manifest's
  setjmp/longjmp pair matters from the first run).
- **XACT**: "WaveBank::Load(): Wave bank version (%i) more recent than this tool supports (%i)",
  "FXCompressor".
- **Trial mode**: "Play trial game", "Continue with trial", "Unlock full game", "You can either
  restart this trial version of Geometry Wars to play again, or alternatively unlock the full
  version of the game to:", the marketplace URLs `/xbos/XeOfferPurchase.ashx`,
  `/xbos/XeContentRefreshLicense.ashx`. Driven by `XamContentGetLicenseMask`: the host sets the
  SDK's `license_mask` to 1 when nothing on the command line did (`port/src/geomwars_app.h`).
- **Live**: "Leaderboards", "Retro Leaderboard", "Evolved Leaderboard", "Change leaderboard",
  "You are not yet ranked on this leaderboard", "Accessing leaderboard", the achievement texts
  ("Survive the first 60 seconds of the game without firing"), `/xstats/syncachievements.ashx`.
- **Storage**: "The game was unable to save your achievements", "please reconnect the Xbox 360
  Memory Unit".
- Five languages: English, French, German, Spanish, Italian.
- `D3D version is %i.%i %s, frame is %i.`: the D3D9 runtime's own banner.

### Translation facts (ReXGlue `bd833a2`, 2026-10-30)
- `.pdata` lists **1,764 functions** (0x82020000 to 0x820E2A34). Round 1 (the scaffold
  manifest) stopped on one error, `b 0x82075438 from 0x8207D764 - target not in any function`:
  a leaf reached by a tail branch, added as the first hint; then `geomwars.exe` linked
  (14 generated translation units, the compile about two minutes at 12 jobs).
- Round 2: `tools/find_missed_functions.py` **34** candidates and `tools/find_code_pointers.py`
  **26**, merged to 34 distinct, added wholesale; no "Unresolved" warning; both finders at 0
  afterwards. `tools/find_vcall_thunks.py`: 0 unregistered forwarders.
- `tools/check_switch_tables.py`: **34 switches, 0 wrong, 0 not replayed** (rounds 1 and 2).
- `tools/check_vector_aliasing.py`: no read-after-write hazard in 9,120 vector instructions.
- **setjmp** 0x82099830 and **longjmp** 0x82099600: the MS CRT pair, found by matching Prey's
  pair (0x822ECC00 / 0x822EC9B0) over 24 instructions with immediates and branch targets masked,
  one hit each.
- **VdSwap**: the import thunk at 0x820E2504 is called from one place, the `bl` at 0x82032A1C:
  the frame hook `GeomWarsFrameMark` (manifest).
- **mtfsf** instructions: four, at 0x8209C708, 0x8209C73C, 0x8209C75C, 0x8209C76C (the C
  runtime's floating-point environment functions, together). **Run 1 (2026-10-30) raised
  C000008F on the audio worker at +2 s** (MXCSR 0x20: the game's mixer `sub_820B33E8` four
  frames under the render-driver callback `sub_82081578`, the outermost guest function on that
  thread): Quake 4's and DOA4's trap. The FPSCR guard is hooked at 0x82081578 and the four
  `mtfsf` (manifest). **Run 2 (2026-10-30), with the hooks: no exception in 90 s**, the audio
  worker's callback (`82092510`, the one XAudio render-driver client) ran throughout.

### Run 2 facts (2026-10-30, `boot.txt`, 90 s, Windows, RTX 4090, 720p windowed)
- **Boots to the game**: the Bizarre Creations logo (a dotted pumpkin) is up at +3 s; one START
  lands on "Select game mode" (Evolved / Retro / Back) with the title's particle field; START
  on Evolved spawns the ship (the blue spawn flash, the grid, the stars); enemies (pinwheels,
  diamonds) arrive; the pause menu is Resume game / Help and options / Leaderboards /
  Achievements / Return to main menu; game over reads "Final score: 0" with "Continue". The HUD
  shows Score, lives and bombs (three hexagons each), **Highscore 10,000** (the table's seed).
- **No sign-in prompt** was shown and no `XamShowSigninUI` call appears in the log: the runtime
  answers the sign-in state without a dialog. **No trial text** anywhere (`license_mask 1`).
- **60 Hz**: every 10 s window of the frame log averaged 60.0 fps (median 16.65 ms, 1% low
  53-55 fps, 80-87% of presents on the 60 Hz vblank); one 238 ms stall in the window that held
  the game over (`XSessionWriteStats` / `XSessionEnd` at +40 s, the stats write at the end of a
  game, no pipeline creation then). 32 pipeline/shader creations in all, all in the first minute.
- **Audio**: the SDL endpoint at 48 kHz stereo; `XAudioSubmitRenderDriverFrame` from the game's
  mixer, queue depth 4-8 frames; not yet listened to (an audio dump is the check).
- Log noise, all once: `gamecontrollerdb.txt` missing, "Achievement store: refusing achievement
  with ID 0" (the store loaded 11 entries), one skipped Vulkan present on the first frame
  ("async placeholder draw"). `XMPGetPlaybackController` polled every 30 ms throughout.
- The game's "Highscore" seed and the achievements come from the profile/achievement store under
  `port/user-smoke` (the smoke run's own user directory).
- `tools/check_switch_tables.py`, `check_vector_aliasing.py`, `find_missed_functions.py`,
  `find_code_pointers.py`: after the first codegen.
