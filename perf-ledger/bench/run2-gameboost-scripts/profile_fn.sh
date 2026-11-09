#!/bin/bash
# profile_fn.sh VARIANT SCEN 'shell code': Ir of running start.sh's function
# definitions followed by the given code (main is not run). For locating
# hot spots, e.g. 'tree_pids 5000 5010' or 'main 5000 5010'.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
v=$1 s=$2 code=$3
run_env "$s"; reset_root "$s"
t=$(mktemp -d)
sed '$d' "$B/var/$v/start/start.sh" > "$t/p.sh"   # drop the final 'main "$@"'
printf '%s\n' "$code" >> "$t/p.sh"
valgrind --tool=callgrind --trace-children=no --callgrind-out-file="$t/cg.out" /bin/bash "$t/p.sh" > /dev/null 2>&1
printf '%-60s Ir=%s\n' "$code" "$(awk '/^(summary|totals):/ {print $2; exit}' "$t/cg.out")"
rm -rf "$t"
