#!/bin/bash
# Usage: patterns.sh MAIN_SH OUTDIR -> OUTDIR/game.re, OUTDIR/excl.re (exactly
# what main.sh passes to gameboostd -m / -x), by evaluating main.sh up to the
# EXCLUDED_PATTERN assignment.
set -eu
main=$1 out=$2
mkdir -p "$out"
script=$(sed -n '1,/^readonly EXCLUDED_PATTERN=/p' "$main")
bash -c "$script"'
printf "%s" "$GAME_PATTERN" > "$1/game.re"
printf "%s" "$EXCLUDED_PATTERN" > "$1/excl.re"' _ "$out"
