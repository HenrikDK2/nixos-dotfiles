#!/bin/bash
# ir.sh VARIANT MODE SCRIPT SCEN [snap]: callgrind instruction count (Ir) of
# the bash process running the script (children not traced: stubs excluded,
# but forked bash subshells are traced with --trace-children=no? no: only the
# main process). Prints "Ir=N".
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
v=$1 mode=$2 script=$3 s=$4
run_env "$s"
if [ "$5" = snap ]; then reset_root "$s" "$B/snap/$s"; else reset_root "$s"; fi
t=$(mktemp -d)
if [ "$script" = start.sh ]; then set -- "$B/var/$v/$mode/start.sh" "${GAME_PIDS[@]}"; else set -- "$B/var/$v/$mode/exit.sh"; fi
valgrind --tool=callgrind --trace-children=no --callgrind-out-file="$t/cg.out" /bin/bash "$@" > /dev/null 2> "$t/vg.err"
ir=$(grep -E '^(summary|totals):' "$t/cg.out" | head -1 | awk '{print $2}')
echo "variant=$v mode=$mode script=$script scen=$s Ir=$ir"
cp "$t/cg.out" "$B/last.cg.out"; rm -rf "$t"
