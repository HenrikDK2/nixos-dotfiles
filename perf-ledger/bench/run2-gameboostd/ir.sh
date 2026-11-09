#!/bin/bash
# ir.sh DRIVER [TREE]  -> deterministic user-space instruction counts (callgrind)
#   scan_desktop / scan_gaming / scan_plain : Ir per full_scan (10 scans, divided)
#   events : Ir in drain_events+check_pending per exec event (3 rounds x 300,
#            one drain per 50 events; events_chunk1: one drain per event)
#   start  : Ir for split_alts of both patterns (once)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
drv=$1; tree=${2:-/dev/shm/gbd_tree}
mapfile -t P < <("$here/patterns.sh" "${MAIN_SH:-$here/../base/system/services/gameboost/scripts/main.sh}")
tmp=$(mktemp -d)
ir() { # name toggle args...
  local name=$1 tog=$2; shift 2
  valgrind --tool=callgrind --callgrind-out-file="$tmp/$name.out" $tog "$drv" "$@" >"$tmp/$name.txt" 2>"$tmp/$name.err"
  grep -E '^(summary|totals):' "$tmp/$name.out" | head -1 | awk '{print $2}'
}
s=$(ir scan_desktop "--toggle-collect=bench_scan*" scan "${P[0]}" "${P[1]}" "$tree/desktop" 10)
pl=$(ir scan_plain "--toggle-collect=bench_scan*" scan "${P[0]}" "${P[1]}" "$tree/plain" 10)
g=$(ir scan_gaming "--toggle-collect=bench_scan*" scan "${P[0]}" "${P[1]}" "$tree/gaming" 10)
e=$(ir events "--toggle-collect=bench_drain* --toggle-collect=bench_check*" events "${P[0]}" "${P[1]}" "$tree/desktop" "$tree/events.txt" 3)
e1=$(ir events1 "--toggle-collect=bench_drain* --toggle-collect=bench_check*" events "${P[0]}" "${P[1]}" "$tree/desktop" "$tree/events.txt" 3 1)
st=$(ir start "--toggle-collect=bench_start*" start "${P[0]}" "${P[1]}" 1)
nev=$(awk 'END{print NR}' "$tree/events.txt")
echo "scan_desktop_Ir_per_scan $((s/10))"
echo "scan_gaming_Ir_per_scan $((g/10))"
echo "scan_plain_Ir_per_scan $((pl/10))"
echo "events_Ir_total $e  per_event $(awk -v e=$e -v n=$nev 'BEGIN{printf "%.1f", e/(3*n)}')"
echo "events_chunk1_Ir_total $e1  per_event $(awk -v e=$e1 -v n=$nev 'BEGIN{printf "%.1f", e/(3*n)}')"
echo "start_Ir $st"
[ -n "${KEEP:-}" ] && { rm -rf "$KEEP"; mv "$tmp" "$KEEP"; echo "kept $KEEP"; } || rm -rf "$tmp"
