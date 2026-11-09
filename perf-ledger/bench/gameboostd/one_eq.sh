#!/bin/bash
# one_eq.sh BIN_A BIN_B [N=400]: start N sleepers with corpus cmdlines
# (games included), then `-1` scans of A and B must print the same lines.
set -eu
source "$(dirname -- "$0")/common.sh"
# data/ (patterns, corpus) comes from any other script, or: MAIN_SH=… here
[[ -s $DATA/game.re && -n ${MAIN_SH:-} ]] || [[ -s $DATA/game.re ]] || { echo "set MAIN_SH=path/to/main.sh" >&2; exit 2; }
[[ -n ${MAIN_SH:-} ]] && ensure_data "$MAIN_SH"
[[ -x $OUT/sleeper ]] || $CC -O2 -Wall "$BENCH/sleeper.c" -o "$OUT/sleeper"
N=${3:-400}
pids=()
while IFS= read -r line && ((${#pids[@]} < N)); do
  IFS=$'\x1f' read -r -a av <<< "$line"
  (exec -a "${av[0]}" "$OUT/sleeper" "${av[@]:1}" > /dev/null 2>&1) &
  pids+=($!)
done < "$DATA/corpus.argv"
sleep 0.5
G=$(cat "$DATA/game.re") X=$(cat "$DATA/excl.re")
"$1" -m "$G" -x "$X" -1 | sort > "$OUT/one_A"
"$2" -m "$G" -x "$X" -1 | sort > "$OUT/one_B"
kill "${pids[@]}" 2> /dev/null || true
wait 2> /dev/null || true
if cmp -s "$OUT/one_A" "$OUT/one_B"; then echo "-1 scan: identical ($(wc -l < "$OUT/one_A") game processes)"; else echo "-1 scan: DIFFERENT"; diff "$OUT/one_A" "$OUT/one_B" | head; exit 1; fi
