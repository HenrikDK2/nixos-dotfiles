#!/bin/bash
# pair_build.sh SRC_A SRC_B OUTBIN: one binary with both variants (pair.c).
set -eu
source "$(dirname -- "$0")/common.sh"
$CC -O2 -Wall -Wno-unused-function -c -DSUF=A -DGBD_SRC="\"$1\"" "$BENCH/core.c" -o "$OUT/core_A.o"
$CC -O2 -Wall -Wno-unused-function -c -DSUF=B -DGBD_SRC="\"$2\"" "$BENCH/core.c" -o "$OUT/core_B.o"
$CC -O2 -Wall "$BENCH/pair.c" "$OUT/core_A.o" "$OUT/core_B.o" -o "$3"
