#!/bin/bash
# Matching path (user space only): callgrind instructions per cmdline and
# native ns per cmdline, A vs B, on the mixed and the desktop-only corpus;
# plus the classification of every line must be identical.
# Usage: match_ab.sh SRC_A SRC_B [TIMING_RUNS=15]
set -eu
source "$(dirname -- "$0")/common.sh"
A=$1 Bsrc=$2 RUNS=${3:-15}
ensure_data "$A"
harness_build match "$A" A
harness_build match "$Bsrc" B
for c in corpus desktop; do
  for v in A B; do "$OUT/match_$v" "$DATA/game.re" "$DATA/excl.re" "$DATA/$c.argv" classify > "$OUT/class_${c}_$v.txt"; done
  if cmp -s "$OUT/class_${c}_A.txt" "$OUT/class_${c}_B.txt"; then echo "classify $c: identical ($(sort "$OUT/class_${c}_A.txt" | uniq -c | tr -s ' \n' ' '))"; else echo "classify $c: DIFFERENT"; exit 1; fi
done
REPS=3
for c in corpus desktop; do
  n=$(wc -l < "$DATA/$c.argv")
  for mode in check scan; do
    for v in A B; do
      fn=bench_$mode
      ir=$(cg_ir "$OUT/cg_${c}_${mode}_$v" "$fn" "$OUT/match_$v" "$DATA/game.re" "$DATA/excl.re" "$DATA/$c.argv" "$mode" $REPS)
      declare "ir_$v=$ir"
    done
    # shellcheck disable=SC2154
    awk -v a="$ir_A" -v b="$ir_B" -v n=$((n*REPS)) -v c=$c -v m=$mode 'BEGIN {printf "Ir/line %-7s %-5s A %8.1f  B %8.1f  delta %+.2f%%\n", c, m, a/n, b/n, (b-a)/a*100}'
  done
done
for c in corpus desktop; do
  : > "$OUT/t_A"; : > "$OUT/t_B"
  for ((i = 0; i < RUNS; ++i)); do
    if ((i % 2)); then order="B A"; else order="A B"; fi
    for v in $order; do "$OUT/match_$v" "$DATA/game.re" "$DATA/excl.re" "$DATA/$c.argv" time 40 >> "$OUT/t_$v"; done
  done
  echo "ns/line $c check  A $(stats < "$OUT/t_A")   B $(stats < "$OUT/t_B")"
done
