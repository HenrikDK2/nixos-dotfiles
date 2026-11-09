#!/bin/bash
# gen_tree.sh [OUT=/dev/shm/gbd_tree]: fake /proc trees desktop/, gaming/,
# plain/ (desktop without the still-running exec-event processes, i.e. no
# Wine/Steam-game command lines) and events.txt
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-/dev/shm/gbd_tree}
rm -rf "$out"
python3 -I "$here/gen_proc.py" "$out"
cp -r "$out/desktop" "$out/plain"
rm -rf "$out"/plain/1[0-9][0-9][0-9][0-9][0-9]
gcc -O2 -static "$here/hold.c" -o /dev/shm/gbd_hold
gcc -O2 -Wall "$here/spawner.c" -o /dev/shm/gbd_spawner
"$here/corpus.sh" "$out" /dev/shm/gbd_corpus.txt
