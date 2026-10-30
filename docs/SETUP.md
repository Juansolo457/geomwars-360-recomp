# Build from your own copy (Windows)

This project ships **source only**. No download contains the game. The game's code is
translated from your copy of the Xbox Live Arcade package on your own PC, and the game data
comes from the same package. You need your own copy of **Geometry Wars: Retro Evolved** for the
Xbox 360 (see step 3).

> Work in progress: see [HANDOFF.md](HANDOFF.md) for where it stands.

The first setup takes about an hour, most of it compiling the ReXGlue SDK. After that, rebuilds
take a few minutes.

## 1. What you need

**Hardware**
- A 64-bit CPU with AVX2 and FMA: Intel Haswell (2013) or AMD Excavator (2015) and newer.
- A GPU with a current **Vulkan 1.2** driver (NVIDIA, AMD or Intel). Vulkan is the only
  renderer.
- About 15 GB of free disk space (toolchain, SDK source and build; the game itself is 15 MB).
- An Xbox controller, plugged in before you start. The game has no keyboard controls.

**Software**
- Windows 10 or 11, 64-bit.
- [Visual Studio 2022](https://visualstudio.microsoft.com/downloads/) with the **Desktop
  development with C++** workload. The build uses its libraries; the compiler is LLVM.
- [Git for Windows](https://git-scm.com/download/win), [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows)
  (`pwsh`) and [Python](https://www.python.org/downloads/) 3.10 or newer, on PATH.

## 2. Set up the toolchain and the SDK

```
pwsh -NoProfile -File tools/setup.ps1
```

It skips any step that is done already:
1. Downloads LLVM 20.1.8, CMake 3.31.8 and Ninja 1.13.1 into `.tools/`, each checked against
   its SHA-256.
2. Clones ReXGlue's source at nightly 0.10.0.24-dev.gbd833a2 into
   `third_party/rexglue-sdk-bd833a2` and applies `tools/patches` (code generator, renderer and
   shader translator changes from graw360-recomp and pgr4-native).
3. Builds the whole SDK with **Vulkan as the only graphics backend** and installs it into
   `third_party/rexglue-sdk-bd833a2/out/install/win-amd64`. The game links that, not ReXGlue's
   prebuilt package, which only has Direct3D 12 on Windows.

## 3. Extract your package

An Xbox Live Arcade game is one file on the console's storage, a LIVE container named by its
hash under `Content\0000000000000000\584107ED\000D0000\`. Point the script at that file:

```
pwsh -NoProfile -File tools/extract.ps1 -Package "<path>\584107ED\000D0000\<the package file>"
```

This unpacks the container's 42 files into `port/assets` (15 MB): `default.xex`, three XACT
wave banks, two `.dat` tables, the sprite TGAs and the icons. The build accepts only the World
release's `default.xex`: title `584107ED`, version 0.0.1.1, SHA-256
`33ae21996edb93478d5eef4f58ae0bec5f5411d3b6a7103a2141bd9f6154ff45`.

## 4. Build

```
pwsh -NoProfile -File tools/build.ps1
```

Translates `default.xex` to C++ (a few seconds for this small image) and compiles the game into
`port/out/build/win-amd64-relwithdebinfo/geomwars.exe`. The first build compiles the generated
code from scratch; later ones only what changed.

## 5. Run

```
pwsh -NoProfile -File tools/launch.ps1 -Windowed
```

`-Scale 1` renders at the console's 720p, the default `-Scale 2` at 1440p, `-Scale 3` at 4K;
without `-Windowed` the game is fullscreen. Your profile, saves and shader cache go in
`port/user` and `port/cache`. The program tells the game it is the full version (the SDK's
`license_mask`); `--license_mask=0` on the command line runs the trial instead.

## Linux and the Steam Deck

Not built yet here. `tools/setup-linux.sh`, `tools/build-linux.sh`, `tools/build-deck.sh` and
`tools/steamdeck/` are the sister projects' scripts, renamed; they become the supported path
once the Windows build is reviewed (PLAN.md, milestone M4).
