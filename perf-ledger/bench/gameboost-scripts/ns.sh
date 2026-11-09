#!/bin/bash
# ns.sh ROOT CMD [ARGS...]: run CMD in a private mount namespace where
# ROOT/sys is /sys, ROOT/run is /run and ROOT/proc is /home (the fake /proc;
# the real /proc stays, bash needs /proc/self for /dev/fd). Needs root.
root=$(realpath -- "$1"); shift
exec unshare -m --propagation private -- /bin/bash -c '
    r=$1; shift
    mount --bind "$r/sys" /sys && mount --bind "$r/run" /run && mount --bind "$r/proc" /home || exit 99
    exec "$@"' ns "$root" "$@"
