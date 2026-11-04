#!/bin/bash

# GameBoost entry point: builds the match patterns, validates them, then
# replaces itself with gameboostd (no bash process stays resident).
#
# gameboostd watches the kernel's exec events instead of scanning /proc on a
# timer, and sleeps on the game's pidfd while it runs. It calls, from this
# directory:
#   start.sh PID...   when a game is detected
#   exit.sh           when the last game exits (or the service stops)
#   notify.sh MSG     desktop notification on each switch

export LC_ALL=C

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly GAMEBOOST_FLAG="/run/gameboost/running.flag"
readonly DAEMON="$SCRIPT_DIR/gameboostd"

readonly GAME_PATTERNS=(
    ".*/proton waitforexitandrun"
    "minecraft.+\.jar"
    "/Games/.+\.(AppImage|x86_64|i386)$"
    "/steamapps/common/.+\.(AppImage|x86_64|i386)"
    "Hytale/.*/(HytaleClient|HytaleServer\.jar)"
    "[A-Za-z]:/.+\\.exe"
    "ProjectZomboid64"
)

readonly EXCLUDED_PATTERNS=(
    # Wine and Windows compatibility processes
    "xalia/xalia.exe"
    "wineserver"
    "/winetricks"
    "C:/windows/.*"

    # Steam runtime, compatibility tools, and internal processes
    "/Steam/legacycompat/"
    "/steamapps/compatdata/"
    "iscriptevaluator\.exe"
    "bin/d3ddriverquery64.exe"
    "pv-adverb"
    "pressure-vessel/bin/pressure-vessel-wrap"
    "pressure-vessel/libexec/steam-runtime-tools-0/srt-bwrap"

    # Game servers and game-specific tools
    "ProjectZomboid64 -servername"
    "/Windower.exe"

    # Mod managers and related tools
    "Black Tree Gaming Ltd/Vortex"
    "Vortex/Vortex.exe"
    "ModOrganizer.exe"
    "MO2/mods"
    "MO2/explorer++"
    "MO2/loot/lootcli.exe"

    # Game launchers, installers, updaters, and runtime dependencies
    "(link2ea://launchgame|/Electronic Arts/EA Desktop)"
    "/*[Ll]auncher*.exe"
    "/*[Ll]aunch[Pp]ad*.exe"
    "[Ss]etup\.exe"
    "[Ii]nstall.*\.exe"
    ".*[Uu]pdate.*\.exe"
    ".*[Rr]edist.*\.exe"
    "/dotnet"
    "/7z.exe" # Exclude archive extraction utilities used by game launchers.

    # Package managers, shell utilities, and scripts
    "(yay|pacman|pgrep|find|xargs|grep|awk|rsync|tar|cat)[[:space:]]"
    "\.sh$"
)

# Build a single "a|b|c" regex from an array, accepting / or \ as separator.
build_slash_tolerant_pattern() {
    local SLASH_CLASS='[/\]' IFS='|'
    printf '%s' "${*//\//$SLASH_CLASS}"
}

readonly GAME_PATTERN=$(build_slash_tolerant_pattern "${GAME_PATTERNS[@]}")
readonly EXCLUDED_PATTERN=$(build_slash_tolerant_pattern "${EXCLUDED_PATTERNS[@]}")

if [[ ! -x "$DAEMON" ]]; then
    echo "ERROR: gameboostd executable not found: $DAEMON" >&2
    exit 1
fi

if ! "$DAEMON" -n -m "$GAME_PATTERN" -x "$EXCLUDED_PATTERN"; then
    echo "ERROR: invalid GAME_PATTERNS / EXCLUDED_PATTERNS" >&2
    exit 1
fi

exec "$DAEMON" -m "$GAME_PATTERN" -x "$EXCLUDED_PATTERN" \
    -d "$SCRIPT_DIR" -f "$GAMEBOOST_FLAG"
