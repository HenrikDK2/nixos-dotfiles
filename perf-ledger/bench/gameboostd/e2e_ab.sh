#!/bin/bash
# Whole daemon (real main loop, fake connector; see e2e.c / e2e_drive.c),
# A vs B: on-CPU ns and wakeups for the measured bursts (interleaved runs),
# plus syscalls per burst from one strace -c run each.
# Usage: e2e_ab.sh SRC_A SRC_B [RUNS=10] [BURSTS=10] [K=1] [LIVE=50] [DUP=0] [GAP_MS=1100]
set -eu
source "$(dirname -- "$0")/common.sh"
A=$1 Bsrc=$2 RUNS=${3:-10} BURSTS=${4:-10} K=${5:-1} LIVE=${6:-50} DUP=${7:-0} GAP=${8:-1100}
ensure_data "$A"
harness_build e2e "$A" A
harness_build e2e "$Bsrc" B
$CC -O2 -Wall "$BENCH/e2e_drive.c" -o "$OUT/e2e_drive"
echo "== e2e bursts=$BURSTS K=$K live=$LIVE% dup=$DUP% gap=${GAP}ms"
: > "$OUT/e2e_res_A"; : > "$OUT/e2e_res_B"
for ((i = 0; i < RUNS; ++i)); do
  if ((i % 2)); then order="B A"; else order="A B"; fi
  for v in $order; do
    "$OUT/e2e_drive" "$OUT/e2e_$v" "$OUT/sleeper" "$DATA/desktop.argv" "$BURSTS" "$K" "$LIVE" "$DUP" "$GAP" | tee -a "$OUT/e2e_log_$v" | awk -v b="$BURSTS" '{print $2 / b, $4 / b}' >> "$OUT/e2e_res_$v"
  done
done
for v in A B; do
  echo "$v cpu_ns/burst $(cut -d" " -f1 "$OUT/e2e_res_$v" | stats)  wakeups/burst $(cut -d" " -f2 "$OUT/e2e_res_$v" | stats)"
  E2E_STRACE="$OUT/e2e_st_$v" "$OUT/e2e_drive" "$OUT/e2e_$v" "$OUT/sleeper" "$DATA/desktop.argv" "$BURSTS" "$K" "$LIVE" "$DUP" "$GAP" > /dev/null
  echo "$v syscalls/burst: $(awk -v b="$BURSTS" 'NF >= 5 && $1 ~ /^[0-9.]+$/ && $NF != "total" {printf "%s %.2f ", $NF, $4 / b; t += $4} END {printf "| total %.2f", t / b}' "$OUT/e2e_st_$v")"
done
