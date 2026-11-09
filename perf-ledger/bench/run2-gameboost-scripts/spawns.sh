#!/bin/bash
# spawns.sh VARIANT MODE SCRIPT SCEN [snap]: deterministic process/syscall
# counts of one run (strace -f). Prints: execve, clone/fork, total syscalls,
# syscalls of the bash process(es) only, and the exec'd program list.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
v=$1 mode=$2 script=$3 s=$4
run_env "$s"
if [ "$5" = snap ]; then reset_root "$s" "$B/snap/$s"; else reset_root "$s"; fi
t=$(mktemp -d)
if [ "$script" = start.sh ]; then set -- "$B/var/$v/$mode/start.sh" "${GAME_PIDS[@]}"; else set -- "$B/var/$v/$mode/exit.sh"; fi
strace -f -qq -o "$t/tr" -e trace=all -e signal=none "$@" > /dev/null 2>&1
# per-pid file handling: strace -f -o writes "PID syscall(...)" lines
execs=$(grep -c ' execve(' "$t/tr")
clones=$(grep -cE ' (clone|clone3|fork|vfork)\(' "$t/tr")
total=$(grep -cvE '^[0-9]+ +(\+\+\+|---)|resumed>' "$t/tr")
# pids that ever execve'd something other than bash = stubs/externals
progs=$(grep -oE ' execve\("[^"]+"' "$t/tr" | sed 's/.*execve("//; s/"$//; s#.*/##' | sort | uniq -c | tr -s ' ' | tr '\n' ',')
# bash-only syscalls: lines from pids whose first execve is a bash script
bpids=$(awk '/ execve\(/ { if (!($1 in f)) { f[$1]=$0 } } END { for (p in f) if (f[p] ~ /\.sh"/) print p }' "$t/tr" | tr '\n' ' ')
bsys=$(awk -v P=" $bpids" 'BEGIN{n=split(P,a," "); for(i=1;i<=n;i++) k[a[i]]=1} ($1 in k) && !/resumed>|\+\+\+|---/ {c++} END{print c+0}' "$t/tr")
echo "variant=$v mode=$mode script=$script scen=$s execve=$execs clone=$clones syscalls_total=$total syscalls_main_bash=$bsys progs=$progs"
cp "$t/tr" "$B/last.strace"; rm -rf "$t"
