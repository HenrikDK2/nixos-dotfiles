#!/bin/bash
# correctness.sh VARIANT [BASE=base]: byte-compare VARIANT against BASE in
# every scenario (start.sh in start/full/render modes, exit.sh on post-start
# snapshots and without a state file, start+exit chains, start.sh over an
# existing state file). Prints one line per case and a summary; diffs go to
# $B/diff/VARIANT/.
# Own fake-root dir per variant, so several variants can be checked at once.
[ -n "$GB_NS" ] || export GB_ROOT_DIR=${GB_ROOT_DIR:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/root-$1}
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
v=$1 base=${2:-base}
out=$B/diff/$v; rm -rf "$out"; mkdir -p "$out"
fail=0 n=0
check() {   # check NAME ARGS... (run1.sh args after VARIANT)
    local name=$1; shift
    "$BENCH/run1.sh" "$base" "$@" > "$out/$name.base"
    "$BENCH/run1.sh" "$v" "$@" > "$out/$name.new"
    n=$((n + 1))
    if cmp -s "$out/$name.base" "$out/$name.new"; then
        echo "same  $name ($(wc -c < "$out/$name.new") bytes)"
        rm -f "$out/$name.base" "$out/$name.new"
    else
        echo "DIFF  $name"; diff "$out/$name.base" "$out/$name.new" > "$out/$name.diff"; fail=$((fail + 1))
    fi
}
START_SCENS=(desk-sysfs desk-ppd desk-nocups desk-x3d desk-pp lap-bat lap-ac small nochildren big)
for s in "${START_SCENS[@]}"; do
    check "start-$s" start start.sh "$s"
    check "full-$s" full start.sh "$s"
    check "chain-$s" full chain "$s"
done
check render-desk-sysfs render start.sh desk-sysfs
check render-nochildren render start.sh nochildren
for s in desk-sysfs desk-ppd lap-bat big exit-reaper exit-wine2 exit-deferred exit-deferred-off; do
    check "exit-$s" start exit.sh "$s" snap
done
check exit-noflag start exit.sh exit-noflag snap
check rerun-desk-sysfs start start.sh desk-sysfs snapflag
echo "cases=$n diffs=$fail"
