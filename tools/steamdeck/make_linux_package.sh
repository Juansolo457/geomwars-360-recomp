#!/usr/bin/env bash
# Assemble the native Linux Steam Deck folder from tools/build-deck.sh's builds (Release and
# RelWithDebInfo; from doax2-360-recomp's): private/steamdeck/GEOMWARS-360-SteamDeck/ with the two
# programs and their .so libraries, the launcher, geomwars.toml, the README and VERSION.txt. The
# disc's files (game/) and the profile (user/) are not put in the folder: they stay on the Deck.
#   tools/steamdeck/make_linux_package.sh                          # into private/steamdeck/
#   tools/steamdeck/make_linux_package.sh --deck deck@steamdeck    # and copy it to the Deck
#   tools/steamdeck/make_linux_package.sh --deck deck@steamdeck --with-game
# --deck copies the folder to ~/recomps/GEOMWARS-360-SteamDeck on that host over SSH; logs/, game/ and
# user/ there are left alone. --with-game also copies port/assets (your package's files, about
# 4.3 GB) to its game/ unless an earlier copy there finished (it leaves .game-complete beside
# game/). The folder holds programs made from your Xbox Live Arcade package and, on the Deck, its data: it never goes
# to GitHub or anywhere else.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
deck=""
with_game=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --deck) deck="$2"; shift ;;
    --with-game) with_game=1 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
if [[ $with_game -eq 1 && -z "$deck" ]]; then
  echo "--with-game needs --deck" >&2
  exit 2
fi
release="$root/port/out/build/deck-amd64-release"
debug="$root/port/out/build/deck-amd64-relwithdebinfo"
for d in "$release" "$debug"; do
  [[ -x "$d/geomwars" ]] || { echo "$d/geomwars is missing: run tools/build-deck.sh (--config Release)" >&2; exit 1; }
done
out="$root/private/steamdeck/GEOMWARS-360-SteamDeck"
rm -rf "$out"
mkdir -p "$out"
cp "$release/geomwars" "$out/geomwars"
cp "$debug/geomwars" "$out/geomwars-relwithdebinfo"
# Every shared library each program loads from beside itself ($ORIGIN).
for d in "$release" "$debug"; do
  for lib in "$d"/*.so; do cp "$lib" "$out/"; done
done
cp "$root/tools/steamdeck/geomwars-linux.sh" "$root/tools/steamdeck/geomwars.toml" \
   "$root/tools/steamdeck/README-SteamDeck-Linux.txt" "$out/"
chmod +x "$out/geomwars" "$out/geomwars-relwithdebinfo" "$out/geomwars-linux.sh"
{
  echo "GEOMWARS 360 recomp, native Linux build for the Steam Deck"
  echo "commit $(git -C "$root" rev-parse --short HEAD) ($(git -C "$root" branch --show-current)), built $(date -r "$release/geomwars" '+%Y-%m-%d %H:%M')"
} > "$out/VERSION.txt"
du -sh "$out"
if [[ -n "$deck" ]]; then
  dest=recomps/GEOMWARS-360-SteamDeck
  # Never a prompt: without a key the Deck accepts (or with its host key unknown), an ssh with
  # no terminal waits for ever. In WSL that is WSL's own ~/.ssh, not Windows'.
  ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10)
  if ! ssh "${ssh_opts[@]}" "$deck" true; then
    echo "Can't reach $deck over SSH without a prompt: add a key it accepts (ssh-copy-id $deck)," \
         "or copy $out to ~/$dest yourself" >&2
    exit 1
  fi
  ssh "${ssh_opts[@]}" "$deck" "mkdir -p ~/$dest"
  # The programs and libraries; logs/, game/ and user/ on the Deck are left alone.
  tar -C "$out" -cf - . | ssh "${ssh_opts[@]}" "$deck" "tar -C ~/$dest -xf -"
  if [[ $with_game -eq 1 ]]; then
    # Not game/default.xex: a copy that stopped partway has that, and the rest would never come.
    if ssh "${ssh_opts[@]}" "$deck" "test -f ~/$dest/.game-complete"; then
      echo "The Deck has game/ already: not copied"
    else
      assets="$(readlink -f "$root/port/assets")"
      [[ -f "$assets/default.xex" ]] || { echo "port/assets/default.xex is missing" >&2; exit 1; }
      echo "Copying the package's files to the Deck's game/ (about 15 MB)"
      ssh "${ssh_opts[@]}" "$deck" "mkdir -p ~/$dest/game"
      tar -C "$assets" -cf - . | ssh "${ssh_opts[@]}" "$deck" "tar -C ~/$dest/game -xf -"
      # Only now: a failed copy ended the script above (pipefail), unmarked.
      ssh "${ssh_opts[@]}" "$deck" "date > ~/$dest/.game-complete"
    fi
  fi
  ssh "${ssh_opts[@]}" "$deck" "cd ~/$dest && ls -la"
fi
