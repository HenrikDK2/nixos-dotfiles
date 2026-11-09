#!/bin/bash
# wall.sh DRV_A DRV_B MODE RUNS [TREE]
#   MODE: scan_desktop | scan_gaming | scan_plain | events | events1
# Runs A and B alternately (ABAB..., RUNS each) pinned to CPU ${CPU:-1};
# each run reports in-process wall, CPU (user+sys) and user-only ns per op.
# Prints median [min..max] for both and the median delta.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
A=$1 B=$2 mode=$3 runs=$4 tree=${5:-/dev/shm/gbd_tree}
mapfile -t P < <("$here/patterns.sh" "${MAIN_SH:-$here/../base/system/services/gameboost/scripts/main.sh}")
case $mode in
  scan_desktop) args=(scan "${P[0]}" "${P[1]}" "$tree/desktop" 300) ;;
  scan_gaming)  args=(scan "${P[0]}" "${P[1]}" "$tree/gaming" 300) ;;
  scan_plain)   args=(scan "${P[0]}" "${P[1]}" "$tree/plain" 300) ;;
  events)       args=(events "${P[0]}" "${P[1]}" "$tree/desktop" "$tree/events.txt" 100) ;;
  events1)      args=(events "${P[0]}" "${P[1]}" "$tree/desktop" "$tree/events.txt" 100 1) ;;
esac
tmp=$(mktemp -d)
for ((i = 0; i < runs; ++i)); do
  for v in A B; do
    d=$A; [ $v = B ] && d=$B
    taskset -c "${CPU:-1}" "$d" "${args[@]}" 2>&1 >/dev/null | awk -v v=$v '/^TIME/{print $4, $6, $8 >> "'"$tmp"'/" v}'
  done
done
stat() { sort -n -k$2 "$tmp/$1" | awk -v k=$2 '{a[NR]=$k} END{m=(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2; printf "%.1f [%.1f..%.1f] n=%d", m, a[1], a[NR], NR}'; }
for k in 1 2 3; do
  name=wall_ns; [ $k = 2 ] && name=cpu_ns; [ $k = 3 ] && name=user_ns
  ma=$(stat A $k); mb=$(stat B $k)
  echo "$mode $name A: $ma  B: $mb  delta: $(awk -v a="${ma%% *}" -v b="${mb%% *}" 'BEGIN{printf "%+.1f%%", (b-a)/a*100}')"
done
rm -rf "$tmp"
