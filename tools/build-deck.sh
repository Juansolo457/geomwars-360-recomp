#!/usr/bin/env bash
# Build geomwars for the Steam Deck: tools/setup-linux.sh and tools/build-linux.sh inside the Ubuntu
# 22.04 container of tools/linux/deck.Containerfile (podman; from graw360-recomp via
# doax2-360-recomp), so the program needs glibc 2.35 at most; a build made on the host needs the
# host's, which SteamOS may not have. The container's SDK checkout and build folder are its own
# (third_party/rexglue-sdk-bd833a2-deck, port/out/build/deck-amd64-<config>), so host builds in the
# same tree are left alone. Then every binary is checked for its glibc requirement.
#   tools/build-deck.sh
#   tools/build-deck.sh --config Release --jobs 12
#   tools/build-deck.sh --rebuild-image      # rebuild the container image first
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image=geomwars-deck-build
glibc_max=2.35
config=RelWithDebInfo
jobs=$(( $(nproc) > 2 ? $(nproc) - 2 : 1 ))
rebuild=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) config="$2"; shift ;;
    --jobs) jobs="$2"; shift ;;
    --rebuild-image) rebuild=1 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
command -v podman >/dev/null || { echo "podman is not installed (docs/SETUP.md, Linux)" >&2; exit 1; }

if [[ $rebuild -eq 1 ]] || ! podman image exists "$image"; then
  podman build -t "$image" -f "$root/tools/linux/deck.Containerfile" "$root/tools/linux"
fi

sdk=/src/third_party/rexglue-sdk-bd833a2-deck
build_rel="port/out/build/deck-amd64-${config,,}"
# The disc files: port/assets may be a link out of the tree; its target is mounted read-only at
# the same path so it resolves.
mounts=(-v "$root:/src")
if [[ -e "$root/port/assets" ]]; then
  real="$(readlink -f "$root/port/assets")"
  case "$real" in "$root"/*) ;; *) mounts+=(-v "$real:$real:ro") ;; esac
fi
podman run --rm --userns=keep-id "${mounts[@]}" -w /src -e HOME=/tmp \
  -e GEOMWARS_SDK_DIR="$sdk" -e GEOMWARS_BUILD_DIR="/src/$build_rel" "$image" \
  bash -c "tools/setup-linux.sh --jobs $jobs && tools/build-linux.sh --config $config --jobs $jobs"

# The newest glibc symbol version each binary needs, and libstdc++'s for the record (GLIBCXX at
# most what a Deck's libstdc++ provides).
fail=0
for f in "$root/$build_rel"/*; do
  [[ -f "$f" && ( -x "$f" || "$f" == *.so ) ]] || continue
  file -b "$f" | grep -q '^ELF' || continue
  need=$(objdump -T "$f" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -1)
  cxx=$(objdump -T "$f" | grep -o 'GLIBCXX_[0-9.]*' | sort -uV | tail -1)
  if [[ -n "$need" && "$(printf '%s\n%s\n' "$need" "$glibc_max" | sort -V | tail -1)" != "$glibc_max" ]]; then
    echo "$(basename "$f"): needs glibc $need, above $glibc_max" >&2
    fail=1
  else
    echo "$(basename "$f"): glibc ${need:-none}${cxx:+, $cxx}"
  fi
done
[[ $fail -eq 0 ]] || exit 1
echo "Deck build: $build_rel"
