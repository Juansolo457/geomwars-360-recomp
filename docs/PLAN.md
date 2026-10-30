# Plan: Geometry Wars: Retro Evolved (Xbox 360), statically recompiled

Written 2026-10-30 from the user's brief and a first look at the package. State and next steps
are in [HANDOFF.md](HANDOFF.md); package and executable facts in [FINDINGS.md](FINDINGS.md).
This file holds the goals, the decisions, the milestones and what the earlier recomps taught
that applies.

## Goal
The Xbox 360 **Geometry Wars: Retro Evolved** (Bizarre Creations, 2005, an Xbox Live Arcade
launch title) running natively on **Windows first, Linux (the Steam Deck, native, no Proton)
second**, its PowerPC code translated to x86-64 with ReXGlue and drawn with **Vulkan**. The
console game as it was: Evolved and Retro, its menus, its bloom and its particles, at the
console's **60 frames a second** and any resolution. **Gamepad only**: the game imports
`XamInputGetState` and nothing for a keyboard (FINDINGS.md); a twin-stick shooter wants the
sticks anyway. Xbox Live leaderboards, achievements and the trial's marketplace flow are out of
scope; the menus must cope with "not signed in" and "no connection" cleanly, and the program
runs the **full game**, not the trial (the licence check is answered by the host).

## Decisions (the user, 2026-10-30)
- **Vulkan is the only render API.** No D3D12 backend, option or fallback. The SDK is built from
  source with `REXGLUE_USE_D3D12=OFF` (DOAX2's recipe) and the host loads the Xenos plugin's
  Vulkan backend by name (`LoadGpuPlugin("xenos", "vulkan")`).
- **Public repository** from day one: `Juansolo457/geomwars-360-recomp`, source only (no builds
  with translated game code, no game files, no keys). Players build from their own package
  (SETUP.md).
- **`master` is locked** like the sister repos: every change through a pull request, the `audit`
  check, an up-to-date branch, every review thread resolved, admins included. **CodeRabbit
  reviews every pull request** (`.coderabbit.yaml`).
- **Ask before builds and test runs** in this repo: the user debugs other games on this PC in
  parallel. Batch the edits, ask once per build-and-run. Never close or kill a game the user
  started.
- **Order: Windows + Vulkan, then Linux + Vulkan.** The native Linux/Deck build is its own
  milestone after the Windows work is reviewed and merged.
- **Use what the sister repos learned.** The template is `../prey-360-recomp` (the newest shape,
  with the finder scripts); the closest executable is `../doa4-360-recomp` (the same launch XDK
  2.0.2135 and a 60 Hz game).

## What is different about an Arcade title
- The game is a **LIVE STFS container**, not a disc: `tools/stfs.py` (new here) reads the file
  table and the hash chains; `tools/extract.ps1 -Package` wraps it. 42 files, 15 MB.
- The executable is **small** (1.1 MB image, 1,764 functions in `.pdata`): codegen takes seconds
  and manifest rounds should be short. It is **LZX-compressed**, so `xex_basic_decrypt.py` can't
  make the analysis image; `xexdump` (the Quake 4 tree's tool) does.
- **Trial or full** is a licence bit (`XamContentGetLicenseMask`), not a different package. The
  SDK's `license_mask` defaults to 0 (trial): `geomwars_app.h` sets it to 1 unless the command
  line said otherwise. The trial path (time limit, "Unlock full game" into `XamShowMarketplaceUI`,
  a stub) stays testable with `--license_mask=0`.
- **Scores live in the profile** (`XamUserWriteProfileSettings`) and the leaderboards on Live
  (`XamUserCreateStatsEnumerator`, a stub): the high score table must work offline from the
  profile, and the leaderboard screens must fail closed.
- **No video, no streaming**: everything loads at start. The audio is XACT wave banks over the
  game's own mixer and XMA contexts.

## Starting points
| Source | What we take |
|---|---|
| `../prey-360-recomp` | the repo shape: `AGENTS.md`, `CONTRIBUTING.md`, `.coderabbit.yaml`, `.github/workflows/audit.yml`, `tools/` (setup, build, smoke, launch, audit, codegen checks, the three finder scripts, RenderDoc scripts, audio dump, the Linux and Deck scripts), `port/src` (app, crash reporter, FPSCR guard, frame timing, autopilot, pad bridge, timer resolution), `docs/` |
| `../doa4-360-recomp` | the same XDK and a 60 Hz game: its pacing findings, the Linux build and the Deck heat lesson (spinners that sleep) |
| `../lotr-conquest-360-recomp` | `readback_resolve=fast` when a game reads a resolve on the CPU, the `vexptefp` underflow patch |
| `../doax2-360-recomp` | the Vulkan-only SDK build, `render_target_path_vulkan=fsi` for EDRAM-exact diagnosis |
| `../graw360-recomp` | the SDK patch set, the Linux/Deck container build |
| `../quake4-360-recomp/third_party/rexglue-sdk-bd833a2` | the shared SDK checkout (junction): ReXGlue `bd833a2` + GRAW's patches + LOTR's `vexptefp-underflow`, tree `12884d9`, built Vulkan-only |
| `../quake4-definitive/build/xexdump` | `xexdump.exe`: the decrypted, decompressed image for the analysis scripts |

## Architecture
```
default.xex (your package) --rexglue codegen--> port/generated/default   (C++, one function per guest function)
                                                    |
port/src        host: GeomWarsApp (Vulkan plugin by name, paths, controllers, license_mask),
                crash reports, frame timing (VdSwap hook), FPSCR guard, autopilot, pad bridge, audio dump
                                                    |
ReXGlue SDK bd833a2 + tools/patches, built from source, REXGLUE_USE_D3D12=OFF:
  runtime  (kernel/XAM, VFS over port/assets, threads, XAudio/XMA, SDL3 window, pads)
  Xenos plugin, Vulkan backend: emulates the console GPU from the game's command buffers
```
Bizarre's own engine: D3D9 with the shaders compiled into the image, TGA sprites through
libpng/libjpeg-era loaders, XACT audio, the game's data in two `.dat` tables.

## Milestones
| # | Milestone | Done when |
|---|---|---|
| M0 | **Repo, toolchain, first translation** | Repo on GitHub, locked, CodeRabbit on, `audit` green; the Prey shape copied and renamed; Vulkan-only SDK linked through the shared junction; the package extracted to `port/assets`; FINDINGS.md; codegen clean (0 wrong switch tables, no vpkd3d128 hazards, the missed-function and code-pointer finders at a fixed point); `geomwars.exe` links |
| M1 | **Title and menu** | The title screen and the main menu drawn on the Vulkan backend without artifacts; a controller moves through them; the sign-in prompt answered; the full game, not the trial; crash reporter and frame log from the first run; reference captures |
| M2 | **A game of Evolved** | Evolved plays from the menu: the grid, the ship, enemies, bullets, bombs, the bloom and the particle field, the score and multiplier HUD, game over and the high score written to the profile; Retro the same; a visual-bug pass against console footage. **The user's first target** |
| M3 | **Windows playable** | 60 presents a second measured and steady at 720p, 1440p and 4K; input lag felt right by the user; audio (effects and music) without gaps; the leaderboard and achievement screens fail closed; the user's play-test |
| M4 | **Native Linux and the Deck** | DOA4's Linux scripts (`setup-linux.sh`, `build-deck.sh`, the Ubuntu 22.04 container); the package in `~/recomps/GeomWars-360-SteamDeck/`; 60 fps on the Deck's screen; the user's Deck run |
| M5 | **Performance and release** | Measured bottlenecks if any (a 2005 Arcade game should be GPU-light); Release build; source-only release with SETUP for Windows and Linux |

Each milestone is at least one pull request. M0-M2 may share one, as the sister repos' did.
**M0 and M1 were reached on 2026-10-30** (run 2: title, mode select, Evolved spawning, pause
menu, game over, 60 fps, no trial text; HANDOFF.md). M2's capture pass is next.

## Lessons applied (what the sister repos paid for; do these before they bite)
**Translation (M0)**
- `check_switch_tables.py` after every codegen: `bd833a2` misreads jump tables on a 64 KB
  boundary (GRAW's shader-parser crash) and oversizes byte-indexed tables (LOTR's two), and
  DOA4 found a halfword-index register bug.
- `setjmp_address`/`longjmp_address` in the manifest from M0 (libpng's and libjpeg's error exits
  longjmp). Done: found by pattern from Prey's pair.
- `find_code_pointers.py` **before the first run**: a method right after a function's last branch
  has no `.pdata` entry and the analyser misses it (Prey's runs 1, 3 and 4 each died on one).
  Add candidates wholesale, then drop any that produce an "Unresolved" codegen warning.
- `check_vector_aliasing.py` every build (`build.ps1` runs it).
- Expect Quake 4's **C000008F on the audio worker** (a mixer thread on an unseeded FP context):
  `port/src/fpscr_guard.cpp` and hooks at the callback's entry and the image's four `mtfsf`
  (FINDINGS.md) the moment it shows.

**First runs (M1-M2)**
- Host **fbo** render targets by default; `--render_target_path_vulkan=fsi` for A/B when a
  band, tint or EDRAM-layout artifact shows (DOAX2's red band). Geometry Wars' bloom is a
  resolve-and-blur chain: the first place to look if the glow is wrong.
- Plugin options only as `--name=value`; the space form is dropped silently.
- `readback_resolve`: `none` by default; LOTR needed `fast` for its CPU-read exposure. Watch for
  a feature that never changes.
- Harmless noise to expect: `cache:` has no device, `default.xexp` probe, devkit-memory
  warnings, `XamNotifyCreateListener` polling, the sign-in state polled every frame.
- `ui_pad.cpp` calls `ImGui::SetNavCursorVisible(true)` on a pad press or A never confirms a
  runtime dialog.
- Shared controllers by default (a virtual XInput pad can take slot 0).
- Crash reporter, the frame counter on the game's one `VdSwap` call, autopilot scripts with
  second-stamped pad presses, a capture every N seconds, `-FreshProfile`.

**60 Hz (M3)**
- DOA4 (the same XDK) presents at 60 with the SDK's vblank pacing patch in the tree; measure
  presents a second over 10 s windows from the frame log before touching anything. On the Deck,
  DOA4 only held 60 once the runtime's spinners slept (heat): take that change when M4 comes.

**Repo and process**
- `python -I tools/audit_repo.py` before every commit; CI runs it over every commit
  (`--history`).
- `tools/setup.ps1` checks the SDK tree hash and install stamp; on this PC `.tools/` and
  `third_party/rexglue-sdk-bd833a2` are junctions to the sister repos' copies. Any new SDK patch
  goes into `tools/patches` here **and** is committed in the shared checkout, and every sister
  repo's `setup.ps1` expected hash moves with it.
- Commit as `juansolo457 <5344231+Juansolo457@users.noreply.github.com>`.
- `HANDOFF.md` updated at the end of every session; `FINDINGS.md` keyed by the XEX hash.

## Review: CodeRabbit
- `.coderabbit.yaml` at the root (Prey's), profile `assertive`, auto-review on `master` PRs,
  drafts off, no poem, walkthrough collapsed; path filters exclude `port/generated/**`,
  `port/assets/**`, `private/**`, `**/out/**`, `third_party/**`, `.tools/**`.
- Path instructions: `port/src/**` (guest/host boundary, Vulkan-only invariant, Linux keeps
  compiling); `port/geomwars_manifest.toml` (every address with its round and evidence);
  `tools/patches/**` (generic, upstreamable); `tools/**` (`python -I`, the audit guards the
  repo); `docs/**` (consistency, no promises of binaries).
- Process: fix what holds up, answer what doesn't with the reason, resolve the thread.
- The CodeRabbit GitHub App covers the account; a new public repo is picked up by it.

## Risks
- **The licence bit:** if the game checks more than bit 0 (some titles read a per-offer mask),
  it still runs as the trial; the fix is the mask value, found from the check's disassembly.
- **Profile-backed scores:** `XamUserReadProfileSettings` for a title-specific setting the SDK
  may not persist; the high score table would reset every run.
- **The Live screens:** Leaderboards, Achievements and the gamercard reach stubs; a hang or a
  crash there is an M3 item (answer the call with "not signed in").
- **Bloom and particles:** render-to-texture resolves and additive blending at 60 Hz are the
  renderer's load here; the Deck's RADV is the proving ground.
- **The 2135 XDK:** DOA4 ran on it, so the kernel surface is known; the audio render driver path
  (`XAudioSubmitRenderDriverFrame`) is the least exercised piece.
