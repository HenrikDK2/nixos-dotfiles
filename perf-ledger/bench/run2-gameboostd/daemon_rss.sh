#!/bin/bash
# daemon_rss.sh TREE BIN...   (root)
# Starts each real gameboostd as the daemon (no-op hook scripts, flag file in
# a temp dir) inside a PID namespace populated from TREE, lets it do its
# startup scan (and enter game mode if TREE has a game), then reports
# VmHWM / VmRSS / Pss (smaps_rollup) / heap size, and stops it with SIGTERM.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
tree=$1; shift
mapfile -t P < <("$here/patterns.sh" "${MAIN_SH:-$here/../base/system/services/gameboost/scripts/main.sh}")
d=$(mktemp -d)
for s in start.sh exit.sh notify.sh; do printf '#!/bin/sh\nexit 0\n' > "$d/$s"; chmod +x "$d/$s"; done
cat > "$d/run.sh" <<EOS
for b in $*; do
  "\$b" -m "\$G" -x "\$X" -d $d -f $d/flag > $d/log 2>&1 &
  pid=\$!
  sleep 1.5
  hwm=\$(awk '/VmHWM/{print \$2}' /proc/\$pid/status)
  rss=\$(awk '/VmRSS/{print \$2}' /proc/\$pid/status)
  pss=\$(awk '/^Pss:/{print \$2}' /proc/\$pid/smaps_rollup)
  h=\$(awk '/\[heap\]/{print \$1}' /proc/\$pid/maps)
  heap=\$(( (0x\${h#*-} - 0x\${h%-*}) / 1024 ))
  kill -TERM \$pid; wait \$pid
  echo "\$(basename \$b) VmHWM_kB=\$hwm VmRSS_kB=\$rss Pss_kB=\$pss heap_kB=\$heap log: \$(head -1 $d/log)"
done
EOS
G=${P[0]} X=${P[1]} unshare --pid --fork --mount-proc /dev/shm/gbd_spawner "$tree" bash "$d/run.sh"
rm -rf "$d"
