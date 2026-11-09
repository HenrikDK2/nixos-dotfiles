#!/bin/bash
# Whole-daemon memory after it has checked Steam/Wine-heavy non-game
# processes (data/nongame.argv: corpus lines that are not games, Steam/Wine
# ones first), A vs B, interleaved. e2e daemons (fake connector), E2E_MEM.
# Usage: mem_e2e.sh SRC_A SRC_B [RUNS=6] [BURSTS=6] [K=200]
set -eu
source "$(dirname -- "$0")/common.sh"
A=$1 Bsrc=$2 RUNS=${3:-6} BURSTS=${4:-6} K=${5:-200}
ensure_data "$A"
if [[ ! -s $DATA/nongame.argv ]]; then
  harness_build match "$A" A
  "$OUT/match_A" "$DATA/game.re" "$DATA/excl.re" "$DATA/corpus.argv" classify > "$OUT/cls.txt"
  python3 - "$DATA/corpus.argv" "$OUT/cls.txt" "$DATA/nongame.argv" <<'PY'
import sys
L = open(sys.argv[1]).read().split('\n')[:-1]; C = open(sys.argv[2]).read().split('\n')
ng = [l for l, c in zip(L, C) if c[0] != 'G']
ng.sort(key=lambda l: not any(k in l for k in ('steam', 'Steam', 'wine', '.exe', 'C:\\', 'Proton', 'pressure-vessel')))
open(sys.argv[3], 'w').write('\n'.join(ng) + '\n')
PY
fi
harness_build e2e "$A" A
harness_build e2e "$Bsrc" B
$CC -O2 -Wall "$BENCH/e2e_drive.c" -o "$OUT/e2e_drive"
: > "$OUT/mem_res_A"; : > "$OUT/mem_res_B"
for ((i = 0; i < RUNS; ++i)); do
  if ((i % 2)); then order="B A"; else order="A B"; fi
  for v in $order; do
    E2E_MEM=1 "$OUT/e2e_drive" "$OUT/e2e_$v" "$OUT/sleeper" "$DATA/nongame.argv" "$BURSTS" "$K" 100 0 1100 >> "$OUT/mem_res_$v"
  done
done
for v in A B; do
  printf '%s ' "$v"
  for k in Rss: Pss: Private_Dirty: Anonymous:; do
    printf '%s %s  ' "$k" "$(awk -v k=$k '{for (i = 1; i < NF; ++i) if ($i == k) print $(i + 1)}' "$OUT/mem_res_$v" | stats)"
  done
  echo
done
