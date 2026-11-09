#!/bin/bash
# Exec-event path (drain_events + check_pending) on real processes through a
# real netlink socket, A vs B: CPU ns per event (thread CPU time, interleaved
# runs), syscalls per event (strace -c, ROUNDS vs 2*ROUNDS difference) and
# user-space instructions per event (callgrind). ns/event is the median over
# runs of each run's median per-round CPU ns per sent event.
# Usage: ev_ab.sh SRC_A SRC_B [RUNS=11] [SCENARIOS="live:dup ..."]
#   scenario live:dup = % of events whose process is alive at check time :
#   % of events repeating the previous PID (exec chains).
set -eu
source "$(dirname -- "$0")/common.sh"
A=$1 Bsrc=$2 RUNS=${3:-11}
SCEN=${4:-"50:0 50:30 100:0 10:0"}
K=${K:-100} ROUNDS=${ROUNDS:-200} SEED=${SEED:-1}
ensure_data "$A"
harness_build evbench "$A" A
harness_build evbench "$Bsrc" B
CORP=$DATA/desktop.argv

sys_counts() { # sys_counts BIN live dup rounds -> "name calls" lines
  strace -c -o "$OUT/st.$$" "$@" > /dev/null 2>&1
  awk 'NF >= 5 && $1 ~ /^[0-9.]+$/ { n = $NF; c = (NF == 6 ? $4 : $4); print n, c }' "$OUT/st.$$"
  rm -f "$OUT/st.$$"
}

for sc in $SCEN; do
  live=${sc%%:*} dup=${sc##*:}
  echo "== scenario live=$live% dup=$dup% K=$K rounds=$ROUNDS"
  : > "$OUT/ev_A"; : > "$OUT/ev_B"
  for ((i = 0; i < RUNS; ++i)); do
    if ((i % 2)); then order="B A"; else order="A B"; fi
    for v in $order; do
      "$OUT/evbench_$v" "$OUT/sleeper" "$CORP" "$ROUNDS" "$K" "$live" "$dup" "$SEED" | awk '{print $8}' >> "$OUT/ev_$v"
    done
  done
  ma=$(stats < "$OUT/ev_A"); mb=$(stats < "$OUT/ev_B")
  echo "ns/event A $ma"
  echo "ns/event B $mb"
  echo "$ma|$mb" | awk -F'|' '{split($1,a," "); split($2,b," "); printf "ns/event median delta %+.2f%%\n", (b[2]-a[2])/a[2]*100}'
  for v in A B; do
    sys_counts "$OUT/evbench_$v" "$OUT/sleeper" "$CORP" "$ROUNDS" "$K" "$live" "$dup" "$SEED" > "$OUT/s1_$v"
    sys_counts "$OUT/evbench_$v" "$OUT/sleeper" "$CORP" $((2 * ROUNDS)) "$K" "$live" "$dup" "$SEED" > "$OUT/s2_$v"
    echo "syscalls/event $v: $(awk -v ev=$((ROUNDS * K)) 'NR==FNR {a[$1]=$2; next} {d=$2-a[$1]; if ($1 != "sendmmsg" && $1 != "clock_gettime" && $1 != "total" && d > 0) {printf "%s %.3f ", $1, d/ev; t += d}} END {printf "| total %.3f", t/ev}' "$OUT/s1_$v" "$OUT/s2_$v")"
    ir=$(cg_ir "$OUT/cg_ev_$v" drain_events --toggle-collect=check_pending "$OUT/evbench_$v" "$OUT/sleeper" "$CORP" 50 "$K" "$live" "$dup" "$SEED")
    echo "Ir/event $v: $(awk -v i="$ir" -v e=$((50 * K)) 'BEGIN {printf "%.1f", i/e}')"
  done
done
