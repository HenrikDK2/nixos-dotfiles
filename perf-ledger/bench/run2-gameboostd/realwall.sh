#!/bin/bash
# realwall.sh TREE DRV_A DRV_B RUNS [REPS]   (root)
# Like wall.sh scan mode, but the drivers scan the REAL /proc of a PID
# namespace populated from TREE (real kernel cost of /proc/PID/cmdline).
# A and B alternate (ABAB...), pinned to CPU ${CPU:-1}; REPS scans per run.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tree=$1 A=$2 B=$3 runs=$4 reps=${5:-300}
mapfile -t P < <("$here/patterns.sh" "${MAIN_SH:-$here/../base/system/services/gameboost/scripts/main.sh}")
tmp=$(mktemp -d)
cat > "$tmp/run.sh" <<EOS
for ((i = 0; i < $runs; ++i)); do
  for v in A B; do
    d=$A; [ \$v = B ] && d=$B
    taskset -c ${CPU:-1} "\$d" scan "\$G" "\$X" /proc $reps 2>&1 >/dev/null | awk -v v=\$v '/^TIME/{print \$4, \$6, \$8 >> "$tmp/" v}'
  done
done
EOS
G=${P[0]} X=${P[1]} unshare --pid --fork --mount-proc /dev/shm/gbd_spawner "$tree" bash "$tmp/run.sh" 2>/dev/null
stat() { sort -n -k$2 "$tmp/$1" | awk -v k=$2 '{a[NR]=$k} END{m=(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2; printf "%.1f [%.1f..%.1f] n=%d", m, a[1], a[NR], NR}'; }
for k in 1 2 3; do
  name=wall_ns; [ $k = 2 ] && name=cpu_ns; [ $k = 3 ] && name=user_ns
  ma=$(stat A $k); mb=$(stat B $k)
  echo "realproc_scan $name A: $ma  B: $mb  delta: $(awk -v a="${ma%% *}" -v b="${mb%% *}" 'BEGIN{printf "%+.1f%%", (b-a)/a*100}')"
done
rm -rf "$tmp"
