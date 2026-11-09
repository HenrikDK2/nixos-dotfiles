#!/bin/bash
# metrics.sh VARIANT...: deterministic counts per variant and case:
# callgrind Ir of the main bash process, and strace execve/clone/syscalls.
# Cases: start.sh (start path / whole run incl. follow-up) and exit.sh.
[ -n "$GB_NS" ] || export GB_ROOT_DIR=${GB_ROOT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/root-metrics}
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
CASES=("start start.sh desk-sysfs" "start start.sh desk-ppd" "start start.sh big" "start start.sh nochildren"
       "full start.sh desk-sysfs" "start exit.sh desk-sysfs snap" "start exit.sh desk-ppd snap" "start exit.sh lap-bat snap")
for v; do
    for c in "${CASES[@]}"; do
        # shellcheck disable=SC2086
        ir=$("$BENCH/ir.sh" "$v" $c | grep -o 'Ir=[0-9]*')
        # shellcheck disable=SC2086
        sp=$("$BENCH/spawns.sh" "$v" $c | grep -oE 'execve=[0-9]+ clone=[0-9]+ syscalls_total=[0-9]+')
        printf '%-6s %-32s %s %s\n' "$v" "$c" "$ir" "$sp"
    done
done
