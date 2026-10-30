#!/bin/bash
# GEOMWARS 360 recomp - the native Linux build on the Steam Deck: no Proton (as doax2-360-recomp's
# doax2-linux.sh and graw360-recomp's graw-linux.sh). Sits in the GEOMWARS-360-SteamDeck folder next to
# the program (geomwars, its .so libraries), geomwars.toml (the Deck's settings, which the program reads
# from its own folder), game/ (the package's files) and user/ (profile and saves).
#   GEOMWARS_DEBUG=1   run geomwars-relwithdebinfo instead (debug info, for crash backtraces)
# Extra arguments go to the game, e.g.  ./geomwars-linux.sh --no-fullscreen
here="$(cd "$(dirname "$0")" && pwd)"
cd "$here" || exit 1
# user/ first: the program puts the profile, saves and shader cache there only if it exists
# (GeomWarsApp::OnConfigurePaths), and the package doesn't carry it. Without it they'd go elsewhere
# and seem lost once it's there, so no start then.
if ! mkdir -p logs user; then
  echo "Can't create logs/ and user/ in $here" >&2
  exit 1
fi
stamp="$(date +%Y%m%d-%H%M%S)"
info="$here/logs/system-$stamp.txt"
program=geomwars
[ "$GEOMWARS_DEBUG" = 1 ] && program=geomwars-relwithdebinfo

# What the Deck has, for a start that fails before the game's own log.
{
  echo "start: $(date)"
  grep -E '^(NAME|VERSION_ID|BUILD_ID)=' /etc/os-release 2>/dev/null
  echo "kernel: $(uname -r)"
  echo "glibc: $(ldd --version 2>&1 | head -1)"
  libstdcxx="$(ldconfig -p 2>/dev/null | awk '/libstdc\+\+\.so\.6 .*x86-64/ {print $NF; exit}')"
  if grep -aq GLIBCXX_3.4.32 "$libstdcxx" 2>/dev/null; then
    echo "libstdc++: $libstdcxx has GLIBCXX_3.4.32 (needed)"
  else
    echo "libstdc++: $libstdcxx LACKS GLIBCXX_3.4.32 (needed): the game can't start"
  fi
  echo "display: DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
  echo "--- controller environment"
  env | grep -E '^(SDL_|SteamVirtualGamepadInfo|SteamAppId|SteamGameId|SteamDeck)' | cut -c1-300
  echo "--- ldd $program"
  ldd "./$program" 2>&1
} > "$info"

# An unzip that dropped the executable bits.
chmod +x ./geomwars ./geomwars-relwithdebinfo 2>/dev/null
if [ ! -f game/default.xex ]; then
  echo "No game/default.xex next to $0: the package's files go in game/" | tee -a "$info" >&2
  exit 1
fi
# The libraries beside the program are found through its $ORIGIN run path.
"./$program" "$@" >> "$here/logs/stdout-$stamp.txt" 2>&1
status=$?
echo "exit status: $status" >> "$info"
exit $status
