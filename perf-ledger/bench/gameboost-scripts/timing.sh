#!/bin/bash
# timing.sh OUTDIR A_SRC NAME=SRC...: the measurement set used for the
# 2026-11-08 run: counts + interleaved wall/CPU (N runs, default 30) in every
# mode. Pass only start.sh candidates or only exit.sh ones, or both.
#   N=30 bash timing.sh /tmp/res $PRISTINE/system/services/gameboost c1=$C1 c2=$C2
B=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
out=$1 a=$2; shift 2
N=${N:-30}
mkdir -p "$out"
ab() { python3 "$B/ab.py" -n "$N" --count --work "$out/work" "$@" A="$a" "${CANDS[@]}"; }
CANDS=("$@")
{
    ab --mode entry
    ab --mode start
    ab --mode entry --scenario desktop-ppd
    ab --mode start --scenario render-busy --hook
    ab --mode exit
    ab --mode exit --real-procs 450
    ab --mode exit-nostate --real-procs 450
} 2>&1 | tee "$out/timing.txt"
