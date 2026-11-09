#!/usr/bin/env bash
# Wall-time A/B (base vs each candidate), alternating order, pinned to one CPU.
# usage: bench/run_ab_all.sh <base main.js> <outdir> <cand main.js>...
set -eu
here=$(cd "$(dirname "$0")" && pwd)
base=$1; out=$2; shift 2
mkdir -p "$out"
for c in "$@"; do
  name=$(basename "$(dirname "$c")")
  node "$here/ab.js" "$base" "$c" --runs "${RUNS:-12}" --iters "${ITERS:-2000}" --cpu "${CPU:-3}" --json > "$out/$name.txt"
done
