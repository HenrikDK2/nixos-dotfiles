#!/bin/bash
# mem.sh BIN [RUNS=10] [WAIT_S=1.5]: start BIN as the real daemon (real proc
# connector, patterns from data/), wait, read /proc/PID/smaps_rollup, stop it.
# Prints median Rss/Pss/Private_Clean/Private_Dirty/Anonymous in kB.
set -eu
source "$(dirname -- "$0")/common.sh"
BIN=$1 RUNS=${2:-10} WAIT=${3:-1.5}
GAME_RE=$(cat "$DATA/game.re") EXCL_RE=$(cat "$DATA/excl.re")
stub=$(mktemp -d)
for f in Rss Pss Private_Clean Private_Dirty Anonymous; do : > "$OUT/mem_$f"; done
for ((i = 0; i < RUNS; ++i)); do
  "$BIN" -m "$GAME_RE" -x "$EXCL_RE" -d "$stub" -f "$stub/flag" > "$OUT/mem_log" &
  pid=$!
  sleep "$WAIT"
  for f in Rss Pss Private_Clean Private_Dirty Anonymous; do
    awk -v k="$f:" '$1 == k {print $2}' "/proc/$pid/smaps_rollup" >> "$OUT/mem_$f"
  done
  kill -TERM "$pid"; wait "$pid" || true
  grep -q Detected "$OUT/mem_log" && echo "WARNING: game mode entered" >&2
done
rm -rf "$stub"
for f in Rss Pss Private_Clean Private_Dirty Anonymous; do printf '%s %s  ' "$f" "$(stats < "$OUT/mem_$f" | awk '{print $2"("$4"-"$6")"}')"; done; echo
