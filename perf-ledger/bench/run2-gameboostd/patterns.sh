#!/bin/bash
# Prints the GAME and EXCLUDED patterns exactly as main.sh builds them
# (line 1: game ERE, line 2: exclude ERE). Usage: patterns.sh path/to/main.sh
set -eu
export LC_ALL=C
src=$(sed -n '/^readonly GAME_PATTERNS=(/,/^readonly EXCLUDED_PATTERN=/p' "$1")
eval "$src"
printf '%s\n%s\n' "$GAME_PATTERN" "$EXCLUDED_PATTERN"
