#!/bin/bash
# Build the stub commands and the write-reject shim into bench/build.
set -e
B=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$B/build/bin"
gcc -O2 -Wall -Wextra -o "$B/build/stub" "$B/stub.c"
gcc -O2 -Wall -Wextra -shared -fPIC -o "$B/build/reject.so" "$B/reject.c" -ldl
for c in systemctl busctl systemd-ac-power renice ionice pgrep killall chrt sleep; do
    ln -sf ../stub "$B/build/bin/$c"
done
# the same without pgrep, for ab.py --real-procs (real pgrep, real /proc)
mkdir -p "$B/build/bin-realpg"
for c in systemctl busctl systemd-ac-power renice ionice killall chrt sleep; do
    ln -sf ../stub "$B/build/bin-realpg/$c"
done
mkdir -p "$B/build/killall-only"
ln -sf ../stub "$B/build/killall-only/killall"
echo "built in $B/build"
