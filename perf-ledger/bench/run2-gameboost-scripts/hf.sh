#!/bin/bash
# hf.sh SCRIPT MODE SCEN snap|- VARIANT...: hyperfine (warmup 3, 20 runs,
# fake root reset by --prepare) pinned to CPU ${GB_CPU:-2}. Not interleaved;
# wall.sh is the alternating measurement.
[ -n "$GB_NS" ] || export GB_ROOT_DIR=${GB_ROOT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/root-hf}
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
script=$1 mode=$2 s=$3 snap=$4; shift 4
run_env "$s"
prep="$BENCH/prep.sh $s"; [ "$snap" = snap ] && prep+=" snap"
cmds=()
for v; do
    if [ "$script" = start.sh ]; then cmds+=("$B/var/$v/$mode/start.sh ${GAME_PIDS[*]}"); else cmds+=("$B/var/$v/$mode/exit.sh"); fi
done
taskset -c "${GB_CPU:-2}" hyperfine -N -w 3 -r 20 --prepare "$prep" "${cmds[@]}" 2>&1 | sed "s#$B/var/##"
