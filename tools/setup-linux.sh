#!/usr/bin/env bash
# Set up what tools/build-linux.sh needs that isn't in the repository, on Linux x86-64 (the Linux
# counterpart of tools/setup.ps1; from graw360-recomp's and doax2-360-recomp's):
#   1. third_party/rexglue-sdk-bd833a2: ReXGlue's source at the nightly 0.10.0.24-dev.gbd833a2's
#      commit with this project's patches (tools/patches), checked against the same patched tree
#      as on Windows (12884d9, GRAW's set plus vexptefp-underflow), then the Linux-only ones on top
#      (fixes in the SDK's runtime that only the Linux build uses);
#   2. that SDK built and installed into its out/install/linux-amd64, RelWithDebInfo and Release:
#      the libraries the game links, the patched Xenos renderer plugin (Vulkan; Linux has no
#      D3D12) and the patched code generator, which the SDK installs from Release only.
# Needs clang (20 or later), CMake 3.25+, Ninja, git, python3 and the SDK's system libraries
# (docs/SETUP.md, "Linux"). The SDK build takes a while the first time (FFmpeg among others).
#   tools/setup-linux.sh             # all of it (skips what is there already)
#   tools/setup-linux.sh --force     # replace an existing SDK source checkout and rebuild
#   tools/setup-linux.sh --jobs 12
# GEOMWARS_SDK_DIR puts the SDK checkout elsewhere (tools/build-deck.sh: the SDK writes its binaries
# into its own tree, so a second build environment needs a second checkout).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sdk="${GEOMWARS_SDK_DIR:-$root/third_party/rexglue-sdk-bd833a2}"
sdk_commit=bd833a2ab69d305f99ddf57418fc38ffec8af93d
# As tools/setup.ps1, in order (what each one fixes is listed there).
sdk_patches=(rexglue-bd833a2-vpkd3d128-alias rexglue-bd833a2-freed-page-resolve
             rexglue-bd833a2-vblank-pacing rexglue-bd833a2-gpu-skip-draws
             pgr4-native/0021-gpu-sample-computed-LOD-pixel-shader-fetches-with-sa
             pgr4-native/0022-gpu-add-a-pixel-shader-modification-for-textures-kno
             rexglue-bd833a2-implicit-gradients-switch rexglue-bd833a2-spirv-exp-adjust
             rexglue-bd833a2-spirv-implicit-gradients rexglue-bd833a2-vexptefp-underflow)
expected_tree=12884d9f3cbcc28abdd88159c8ed93651bc9192d  # after the last patch (tools/setup.ps1)
# Then, in their own commit. graw360-recomp's four (its Linux tree is f481d5e after them): the
# game's launch path given to the title; a fault no handler claims crashes with a host backtrace
# instead of re-faulting forever, and RenderDoc is used only when it's already in the process
# (SteamOS installs librenderdoc.so, so a plain dlopen loaded it into every run); guest memory's
# shared segment is unlinked once created (named, it outlived every hard exit in /dev/shm and
# filled it); the crash report's backtrace runs under a 5 s alarm.
# doax2-360-recomp's three, for this engine (GEOMWARS imports the same system-link socket calls and
# uses XAPI fibers): guest ports below 1024 used 10000 higher (Linux refuses low ports to a normal
# user; the system-link VDP socket binds port 1000), for binds and, in destinations and sources,
# only on the low ports the title bound itself (here, not yet in DOAX2: its peers bind the same
# ones wherever they are, and a server's port 80 or 53 keeps its number); ioctlsocket's Winsock
# commands (FIONBIO, FIONREAD) translated to Linux's, any other passed on as it is (here, not yet
# in DOAX2), and a failed socket call's errno reported to the guest as its Winsock code
# (WSAEWOULDBLOCK, ...): DOAX2 never drew a first frame without both;
# and a thread fiber destroyed from another thread no longer clears that thread's current fiber
# (a guest thread's exit crashed the main thread's next SwitchToFiber).
# doa4-360-recomp's two, from its Steam Deck profile: a wait on several handles sleeps
# until one may be signaled (it slept 0 ms in its last millisecond, so an alertable one, run in
# 1 ms slices, spun a core: the audio worker's), and the GPU command thread looks up a register's
# info only when the debug message it's for would be written (a tenth of that thread's time).
linux_patches=(rexglue-bd833a2-launch-title-path rexglue-bd833a2-linux-crash-renderdoc
               rexglue-bd833a2-linux-shm-unlink rexglue-bd833a2-linux-crash-watchdog
               rexglue-bd833a2-bind-low-port rexglue-bd833a2-linux-socket-ioctl
               rexglue-bd833a2-linux-fiber-destroy rexglue-bd833a2-linux-wait-multiple
               rexglue-bd833a2-register-info-log)
linux_tree=2f06e47aef4c9f4944a39d248e82a3ea1e8c216a
# The Linux trees earlier versions of this script made (c66e664 with DOAX2's socket patches as
# DOAX2 has them, ff9a4d1 before the profile's two patches, 5e1f93a with bind-low-port by address
# range): a checkout at one of them moves to linux_tree by itself. Any other tree is a change of
# someone's own and is left for --force.
old_linux_trees=(c66e6647e87ffc80a0066b97bfcbcb47ec039123 ff9a4d102e20ddb5ad2dd2c6e21337dd3bfd2a0a
                 5e1f93a77ba59316d1a3fc1bbb0397dbce8192c3)
force=0
jobs=$(( $(nproc) > 2 ? $(nproc) - 2 : 1 ))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=1 ;;
    --jobs) jobs="$2"; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

for cmd in git python3 cmake ninja clang clang++; do
  command -v "$cmd" >/dev/null || { echo "$cmd is not installed (docs/SETUP.md, Linux)" >&2; exit 1; }
done

apply_patches() {  # <patch>...
  for name in "$@"; do
    # The patches are LF; a Windows checkout of this repository may have given them CRLF.
    sed 's/\r$//' "$root/tools/patches/$name.patch" | git -C "$sdk" apply -
  done
  git -C "$sdk" add -A
}

# 1. The SDK source with this project's patches.
if [[ -d "$sdk" && $force -eq 1 ]]; then rm -rf "$sdk"; fi
if [[ -d "$sdk" ]]; then
  # A finished checkout has HEAD at the expected tree and no changes of its own; anything else
  # stopped partway or was changed by hand, and replacing it is --force's job.
  head=$(git -C "$sdk" rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null || true)
  changes=$(git -C "$sdk" status --porcelain --ignore-submodules=all 2>/dev/null || true)
  # An older set of the Linux patches (one of old_linux_trees), in their own commit on the patched
  # tree: that commit goes, and they're applied again below. The build folder stays, so the SDK
  # rebuilds only what changed.
  if [[ " ${old_linux_trees[*]} " == *" $head "* && -z "$changes" &&
        "$(git -C "$sdk" log -1 --format=%s 2>/dev/null)" == 'geomwars-360-recomp Linux patches' &&
        "$(git -C "$sdk" rev-parse --verify --quiet 'HEAD~1^{tree}' 2>/dev/null)" == "$expected_tree" ]]; then
    echo 'SDK source: replacing an older set of the Linux patches'
    git -C "$sdk" reset --quiet --hard HEAD~1
    head=$expected_tree
  fi
  if [[ ( "$head" != "$expected_tree" && "$head" != "$linux_tree" ) || -n "$changes" ]]; then
    echo "SDK source: $sdk is incomplete, on another commit or changed by hand: run with --force" >&2
    exit 1
  fi
  echo "SDK source: $sdk exists already (--force replaces it)"
else
  echo 'SDK source: cloning ReXGlue'
  mkdir -p "$(dirname "$sdk")"
  git clone --no-checkout https://github.com/rexglue/rexglue-sdk.git "$sdk"
  git -C "$sdk" checkout --quiet --detach "$sdk_commit"
  echo "SDK source: applying ${#sdk_patches[@]} patches"
  apply_patches "${sdk_patches[@]}"
  tree=$(git -C "$sdk" write-tree)
  if [[ "$tree" != "$expected_tree" ]]; then
    echo "The patched SDK tree is $tree, not $expected_tree: tools/patches changed without" \
         "tools/setup-linux.sh, or a patch applied differently" >&2
    exit 1
  fi
  git -C "$sdk" -c user.name=geomwars-360-recomp -c user.email=setup@localhost commit --quiet \
      -m 'geomwars-360-recomp patches'
  git -C "$sdk" switch --quiet -c geomwars
fi
# The Linux-only patches.
if [[ "$(git -C "$sdk" rev-parse 'HEAD^{tree}')" == "$expected_tree" ]]; then
  echo "SDK source: applying ${#linux_patches[@]} Linux patch(es)"
  apply_patches "${linux_patches[@]}"
  tree=$(git -C "$sdk" write-tree)
  if [[ "$tree" != "$linux_tree" ]]; then
    echo "The SDK tree with the Linux patches is $tree, not $linux_tree" >&2
    exit 1
  fi
  git -C "$sdk" -c user.name=geomwars-360-recomp -c user.email=setup@localhost commit --quiet \
      -m 'geomwars-360-recomp Linux patches'
fi
# Every run, so one that stopped while fetching them picks up where it left off.
echo 'SDK source: fetching its submodules'
git -C "$sdk" submodule update --init --recursive

# 2. Build and install the SDK (Vulkan is the only graphics backend on Linux).
install="$sdk/out/install/linux-amd64"
# RelWithDebInfo libraries carry the SDK's "rd" postfix (librexgpu-xenosrd.so); the code generator
# is Release's bin/rexglue. The install records the source tree it was built from, so a new patch
# rebuilds it.
stamp="$install/geomwars-sdk-tree"
if [[ -x "$install/bin/rexglue" && -f "$install/lib/librexruntimerd.so" && $force -eq 0 &&
      "$(cat "$stamp" 2>/dev/null)" == "$linux_tree" ]]; then
  echo "SDK: built ($install)"
else
  (cd "$sdk" && cmake --preset linux-amd64 -DREXGLUE_BUILD_TESTS=OFF)
  for config in RelWithDebInfo Release; do
    echo "SDK: building $config ($jobs jobs)"
    cmake --build "$sdk/out/build/linux-amd64" --config "$config" --parallel "$jobs"
    cmake --install "$sdk/out/build/linux-amd64" --config "$config" --prefix "$install"
  done
  [[ -x "$install/bin/rexglue" ]] || { echo "SDK build: $install/bin/rexglue is missing" >&2; exit 1; }
  echo "$linux_tree" > "$stamp"
fi
echo 'Setup done. Next: the package's files in port/assets (docs/SETUP.md), then tools/build-linux.sh.'
