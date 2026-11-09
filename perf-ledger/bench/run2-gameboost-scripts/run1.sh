#!/bin/bash
# run1.sh VARIANT MODE WHAT SCEN [snap|snapflag]: one run in a fresh fake root,
# then print the dump (fake sysfs/run contents, written proc files, command
# log, exit status, stdout, stderr; $R replaced by ROOT).
#   WHAT: start.sh | exit.sh | chain (start.sh, then exit.sh in the same root)
#   snap: start from the scenario's post-start snapshot; snapflag: the same
#   with running.flag present (start.sh re-run over an existing state file).
# With MODE=render a helper raises three game threads' schedstat 0.5 s into
# the 1 s sample, so the render-thread pick has something to pick.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
v=$1 mode=$2 what=$3 s=$4
run_env "$s"
export GB_RESET_PROC=1
case $5 in
    snap) reset_root "$s" "$B/snap/$s" ;;
    snapflag) reset_root "$s" "$B/snap/$s"; echo pid=5000 > "$R/run/gameboost/running.flag" ;;
    *) reset_root "$s" ;;
esac
bump() {
    sleep 0.5
    local t base
    for t in 6000:900000000 6001:300000000 6002:500000000 6003:100000000; do
        read -r base _ < "$R/proc/5010/task/${t%:*}/schedstat"
        echo "$((base + ${t#*:})) 0 0" > "$R/proc/5010/task/${t%:*}/schedstat"
    done
}
t0=$EPOCHREALTIME
case $what in
    start.sh | chain)
        [ "$mode" = render ] && { bump & }
        "$B/var/$v/$mode/start.sh" "${GAME_PIDS[@]}" > "$R/.out" 2> "$R/.err"; rc=$?
        wait
        if [ "$what" = chain ]; then
            rm -f "$R/run/gameboost/running.flag"
            "$B/var/$v/$mode/exit.sh" >> "$R/.out" 2>> "$R/.err"; rc+=" $?"
        fi ;;
    exit.sh) "$B/var/$v/$mode/exit.sh" > "$R/.out" 2> "$R/.err"; rc=$? ;;
esac
t1=$EPOCHREALTIME
dump_root
printf '== rc %s\n== stdout\n' "$rc"; sed "s#$R#ROOT#g" "$R/.out"; printf '== stderr\n'; sed -E -e "s#$R#ROOT#g" -e "s#$B/var/$v/#VAR/#g" -e "s/: line [0-9]+: /: line N: /" "$R/.err"
[ "$mode" = render ] && echo "== render-mode wall >= 1s: $(( (${t1/./} - ${t0/./}) >= 1000000 ))"
