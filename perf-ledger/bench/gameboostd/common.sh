# shellcheck shell=bash
# Sourced by the *_ab.sh scripts. BENCH = this directory, OUT = build/output
# directory (override with OUT=...), data built on first use.
BENCH=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUT=${OUT:-$BENCH/out}
DATA=$BENCH/data
CC=${CC:-gcc}
mkdir -p "$OUT" "$DATA"

# MAIN_SH: main.sh whose patterns are used (default: next to source A).
ensure_data() {
  local main=${MAIN_SH:-$(dirname -- "$1")/main.sh}
  [[ $1 == */main.sh ]] && main=$1
  "$BENCH/patterns.sh" "$main" "$DATA"
  [[ -s $DATA/corpus.argv ]] || python3 "$BENCH/gen_corpus.py" 2000 1 > "$DATA/corpus.argv"
  [[ -s $DATA/desktop.argv ]] || python3 "$BENCH/gen_corpus.py" 2000 2 desktop > "$DATA/desktop.argv"
  [[ -s $DATA/corpus.lines ]] || python3 "$BENCH/mklines.py" "$DATA/corpus.argv" > "$DATA/corpus.lines"
  [[ -s $DATA/desktop.lines ]] || python3 "$BENCH/mklines.py" "$DATA/desktop.argv" > "$DATA/desktop.lines"
  [[ -x $OUT/sleeper ]] || $CC -O2 -Wall "$BENCH/sleeper.c" -o "$OUT/sleeper"
  export GAME_RE EXCL_RE
  GAME_RE=$(cat "$DATA/game.re") EXCL_RE=$(cat "$DATA/excl.re")
}

# harness_build NAME SRC TAG -> $OUT/NAME_TAG (harness NAME.c including SRC)
harness_build() {
  $CC -O2 -Wall -Wno-unused-function -DGBD_SRC="\"$2\"" "$BENCH/$1.c" -o "$OUT/$1_$3"
}

# median/min/max of numbers on stdin
stats() {
  sort -g | awk '{a[NR]=$1} END {m = NR % 2 ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2;
    printf "median %s min %s max %s n %d", m, a[1], a[NR], NR}'
}

# callgrind Ir of one run: cg_ir OUTFILE TOGGLEFN CMD... (TOGGLEFN - = whole run)
cg_ir() {
  local f=$1 t=$2; shift 2
  local tg=(--toggle-collect="$t")
  [[ $t == - ]] && tg=()
  valgrind --tool=callgrind "${tg[@]}" --callgrind-out-file="$f.%p" "$@" > /dev/null 2>&1
  # the largest file is the harness process itself (forked children too)
  local best=0 x
  for x in "$f".*; do
    local ir; ir=$(awk '/^summary:/ {print $2}' "$x")
    (( ir > best )) && best=$ir
    rm -f "$x"
  done
  echo "$best"
}
