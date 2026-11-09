#!/bin/bash
# equiv.sh SRC_A SRC_B [N=200000] [SEED=7]: classification of N fuzz lines
# (gen_fuzz.py) plus both corpora must be identical for A and B.
set -eu
source "$(dirname -- "$0")/common.sh"
ensure_data "$1"
N=${3:-200000} SEED=${4:-7}
python3 "$BENCH/gen_fuzz.py" "$N" "$SEED" > "$OUT/fuzz.argv"
harness_build match "$1" EA
harness_build match "$2" EB
for f in "$OUT/fuzz.argv" "$DATA/corpus.argv" "$DATA/desktop.argv"; do
  "$OUT/match_EA" "$DATA/game.re" "$DATA/excl.re" "$f" classify > "$OUT/eq_A"
  "$OUT/match_EB" "$DATA/game.re" "$DATA/excl.re" "$f" classify > "$OUT/eq_B"
  if cmp -s "$OUT/eq_A" "$OUT/eq_B"; then
    echo "$(basename "$f"): identical ($(sort "$OUT/eq_A" | uniq -c | tr -s ' \n' ' '))"
  else
    echo "$(basename "$f"): DIFFERENT"; exit 1
  fi
done
