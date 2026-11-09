#!/bin/bash
# realproc.sh TREE BIN...   (root; run from anywhere)
# In a fresh PID namespace whose /proc holds exactly the processes of
# TREE/<pid>/cmdline (spawned by gbd_spawner), for each real gameboostd
# binary: `-1` output (md5 + line count), syscall counts (strace -f -c), and
# callgrind Ir of the whole `-1` run (cold: startup, lazy regcomp, one scan).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tree=$1; shift
mapfile -t P < <("$here/patterns.sh" "${MAIN_SH:-$here/../base/system/services/gameboost/scripts/main.sh}")
out=$(mktemp -d)
cat > "$out/run.sh" <<EOS
set -u
for b in $*; do
  n=\$(basename \$b)
  "\$b" -1 -m "\$G" -x "\$X" > $out/\$n.out
  strace -f -c -o $out/\$n.strace "\$b" -1 -m "\$G" -x "\$X" > /dev/null
  valgrind --tool=callgrind --callgrind-out-file=$out/\$n.cg "\$b" -1 -m "\$G" -x "\$X" > /dev/null 2>&1
done
EOS
G=${P[0]} X=${P[1]} unshare --pid --fork --mount-proc /dev/shm/gbd_spawner "$tree" bash "$out/run.sh"
for b in "$@"; do
  n=$(basename "$b")
  sc=$(awk '$NF=="total"{print $4}' "$out/$n.strace")
  ir=$(grep -E '^summary:' "$out/$n.cg" | awk '{print $2}')
  echo "$n out_md5=$(md5sum < "$out/$n.out" | cut -c1-12) matches=$(wc -l < "$out/$n.out") syscalls=$sc Ir=$ir"
done
[ -n "${KEEP:-}" ] && { rm -rf "$KEEP"; mv "$out" "$KEEP"; } || rm -rf "$out"
