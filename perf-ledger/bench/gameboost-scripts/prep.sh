#!/bin/bash
# prep.sh SRC_GAMEBOOST_DIR OUTDIR: copy start.sh/exit.sh from SRC with "/proc/"
# rewritten to "/home/" (same length, so expansions cost the same; ns.sh
# mounts the fake /proc there). /sys and /run are used as they are.
# NO_PROC_REWRITE=1 keeps /proc (ab.py --real-procs: exit.sh on the real one).
set -e
src=$1 out=$2
mkdir -p "$out"
for f in start.sh exit.sh; do
    if [ "${NO_PROC_REWRITE:-}" = 1 ]; then cp "$src/$f" "$out/$f"
    else sed -e 's#/proc/#/home/#g' "$src/$f" > "$out/$f"; fi
    chmod +x "$out/$f"
done
