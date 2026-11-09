#!/bin/bash
# run.sh SRC SCENARIO MODE ROOT OUT [GENARGS...]
#   SRC   directory holding start.sh and exit.sh (e.g. REPO/system/services/gameboost)
#   MODE  start      start.sh through its follow-up steps (sleep stubbed, hook bumps schedstat)
#         entry      start.sh until its first sleep (game-mode entry)
#         exit       exit.sh on the freshly generated scenario (no state: fallback paths,
#                    plus whatever /run files the scenario seeds)
#         startexit  start (full) then exit.sh, snapshot after each
#   ROOT  fake root path (regenerated), OUT  result dir (snapshot, logs)
# The scripts run in a mount namespace (ns.sh): ROOT/sys -> /sys, ROOT/run -> /run,
# ROOT/proc -> /home (prep.sh rewrites /proc/ to /home/).
set -u
B=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
src=$1 scen=$2 mode=$3 root=$4 out=$5
shift 5
src=$(realpath -- "$src")
rm -rf "$out"; mkdir -p "$out" "$root"
out=$(realpath -- "$out") root=$(realpath -- "$root")
python3 "$B/gen.py" "$root" "$scen" "$@" >/dev/null || exit 1
"$B/prep.sh" "$src" "$root/scripts" || exit 1
envs=(LC_ALL=C PATH="$B/build/bin:/usr/bin:/bin" GB_LOG="$out/calls.log" GB_RESP="$root/resp"
      GB_FLAG=/run/gameboost/running.flag GB_SLEEP_HOOK="$root/sleep_hook")
while IFS= read -r e; do [ -n "$e" ] && envs+=("$e"); done < "$root/env"
grep -q '^GB_REJECT=' "$root/env" && envs+=(LD_PRELOAD="$B/build/reject.so")
read -r -a args < "$root/args"
snap() { # snap NAME: every file of sys/ and run/, and proc/ files written to
    (cd "$root" && { find sys run -type f; find proc -type f -newer args; } | LC_ALL=C sort |
        while IFS= read -r f; do printf '== %s\n' "$f"; cat "$f"; echo; done) > "$out/$1.tree"
}
runit() { # runit NAME SCRIPT ARGS...
    local n=$1; shift
    echo "--- $n" >> "$out/calls.log"
    "$B/ns.sh" "$root" env -i "${envs[@]}" "$@" > "$out/$n.stdout" 2> "$out/$n.stderr"
    echo $? > "$out/$n.rc"
    # bash prefixes errors with the script line, which moves with any patch
    sed -i "s#$root#ROOT#g; s#^\(ROOT/scripts/[a-z]*\.sh\): line [0-9]*:#\1: line N:#" \
        "$out/$n.stdout" "$out/$n.stderr"
}
touch -d '2000-01-01' "$root/args"
find "$root/sys" "$root/proc" "$root/run" -type f -exec touch -d '2000-01-01' {} +
case $mode in
    start) runit start bash "$root/scripts/start.sh" "${args[@]}"; snap start ;;
    entry) envs+=(GB_SLEEP_STOP=1 GB_SLEEP_HOOK=); runit start bash "$root/scripts/start.sh" "${args[@]}"; snap start ;;
    exit) runit exit bash "$root/scripts/exit.sh"; snap exit ;;
    startexit)
        runit start bash "$root/scripts/start.sh" "${args[@]}"; snap start
        rm -f "$root/run/gameboost/running.flag"
        runit exit bash "$root/scripts/exit.sh"; snap exit ;;
esac
sed -i "s#$root#ROOT#g" "$out/calls.log"
# IGNORE_CALLS (ERE): call-log lines a candidate is expected to drop or add
if [ -n "${IGNORE_CALLS:-}" ]; then
    grep -Ev -- "$IGNORE_CALLS" "$out/calls.log" > "$out/calls.log.f"
    mv "$out/calls.log.f" "$out/calls.log"
fi
