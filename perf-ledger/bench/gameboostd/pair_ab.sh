#!/bin/bash
# Paired CPU-time A/B (see pair.c). Usage:
#   pair_ab.sh SRC_A SRC_B ev   [REPS=5] [SCENARIOS="50:0 50:30 100:0 10:0"]
#   pair_ab.sh SRC_A SRC_B scan [REPS=5] [NPROCS=800]
# Each repetition is a fresh process (ROUNDS rounds, default 1000 for ev,
# 200 for scan); the line per repetition is printed as is.
set -eu
source "$(dirname -- "$0")/common.sh"
A=$1 Bsrc=$2 MODE=$3 REPS=${4:-5}
ensure_data "$A"
"$BENCH/pair_build.sh" "$A" "$Bsrc" "$OUT/pair"
if [[ $MODE == ev ]]; then
  for sc in ${5:-"50:0 50:30 100:0 10:0"}; do
    echo "== ev live=${sc%%:*}% dup=${sc##*:}% K=${K:-100}"
    for ((i = 0; i < REPS; ++i)); do
      "$OUT/pair" ev "$OUT/sleeper" "$DATA/desktop.argv" "${ROUNDS:-1000}" "${K:-100}" "${sc%%:*}" "${sc##*:}" $((i + 1))
    done
  done
else
  echo "== scan with ${5:-800} extra processes"
  for ((i = 0; i < REPS; ++i)); do
    "$OUT/pair" scan "$OUT/sleeper" "$DATA/corpus.argv" "${ROUNDS:-200}" "${5:-800}"
  done
fi
