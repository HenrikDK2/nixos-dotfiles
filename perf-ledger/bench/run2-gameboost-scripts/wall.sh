#!/bin/bash
# wall.sh ROUNDS SCRIPT MODE SCEN [snap|-] VARIANT...: alternating wall-time
# comparison (abrun) pinned to CPU ${GB_CPU:-2}. The fake root is reset
# (untimed) before every run. Raw samples -> $B/raw-<...>.txt
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
rounds=$1 script=$2 mode=$3 s=$4 snap=$5; shift 5
run_env "$s"
prep="$BENCH/prep.sh $s"; [ "$snap" = snap ] && prep+=" snap"
cmds=()
for v; do
    if [ "$script" = start.sh ]; then cmds+=("$B/var/$v/$mode/start.sh ${GAME_PIDS[*]}"); else cmds+=("$B/var/$v/$mode/exit.sh"); fi
done
export ABRUN_RAW=$B/raw-$script-$mode-$s-$(IFS=_; echo "$*").txt
ABRUN_CPU=${GB_CPU:-2} "$B/abrun" "$rounds" 3 "$prep" "${cmds[@]}" | sed "s#$B/var/##"
