#!/bin/bash
# compare.sh SRC_A SRC_B [WORKDIR]: run every scenario/mode with both sources
# and diff stdout, stderr, exit codes, the stub call log and the final fake
# sysfs/run/proc contents. Prints one line per case; exit 1 on any mismatch.
# Env: SCENARIOS, MODES (lists), GENARGS (gen.py args), IGNORE_CALLS (ERE of
# stub-call lines to drop from both logs, for a candidate that removes a call),
# SORT_CALLS=1 (compare each call's arguments as a sorted list: for a change
# that only reorders PIDs).
B=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
a=$1 b=$2 wd=${3:-$(mktemp -d)}
mkdir -p "$wd"; wd=$(realpath "$wd")
SCENARIOS=${SCENARIOS:-"desktop-sysfs desktop-ppd laptop-battery laptop-ac reentry odd-procs powerplay-ppd-refused render-busy render-busy-nopref"}
MODES=${MODES:-"startexit entry exit"}
fail=0
for s in $SCENARIOS; do
    for m in $MODES; do
        for side in a b; do
            src=$a; [ $side = b ] && src=$b
            bash "$B/run.sh" "$src" "$s" "$m" "$wd/root" "$wd/$side" $GENARGS
        done
        if [ "${SORT_CALLS:-}" = 1 ]; then
            for side in a b; do
                while read -r -a w; do printf '%s\n' "${w[0]} $(printf '%s\n' "${w[@]:1}" | sort | tr '\n' ' ')"; done \
                    < "$wd/$side/calls.log" > "$wd/$side/calls.sorted" && mv "$wd/$side/calls.sorted" "$wd/$side/calls.log"
            done
        fi
        if d=$(diff -r "$wd/a" "$wd/b"); then
            printf 'SAME  %-24s %-10s calls=%s\n' "$s" "$m" "$(grep -vc '^---' "$wd/a/calls.log")"
        else
            printf 'DIFF  %-24s %-10s\n' "$s" "$m"; echo "$d" | head -20; fail=1
        fi
    done
done
exit $fail
