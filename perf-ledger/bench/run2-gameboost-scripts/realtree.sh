#!/bin/bash
# realtree.sh W: real-kernel check of the children-file walk (c3) against the
# /proc scan (base): both tree_pids functions on a live process tree started
# here (sleep processes, killed by pid at the end; nothing else is touched).
export LC_ALL=C
W=$1
extract() { sed -n '/^tree_pids()/,/^}/p' "$1"; }
eval "$(extract "$W/base/system/services/gameboost/scripts/start.sh" | sed 's/^tree_pids()/tree_base()/')"
eval "$(extract "$W/c3/system/services/gameboost/scripts/start.sh" | sed 's/^tree_pids()/tree_new()/')"
[ -e /proc/thread-self/children ] || { echo "no children files on this kernel"; exit 1; }
( for _ in 1 2 3; do ( sleep 30 & sleep 30 & ( sleep 30 & wait ) & wait ) & done
  sleep 30 & sleep 30 & sleep 30 & wait ) &
root=$!
sleep 0.5
tree_base "$root"; a="${TREE[*]}"
tree_new "$root"; b="${TREE[*]}"
tree_base "$root" $$; c="${TREE[*]}"
tree_new "$root" $$; d="${TREE[*]}"
echo "tree from root: n=$(wc -w <<< "$a") identical=$([ "$a" = "$b" ] && echo yes || echo no)"
echo "tree from root + this shell: n=$(wc -w <<< "$c") identical=$([ "$c" = "$d" ] && echo yes || echo no)"
echo "order: $a"
# shellcheck disable=SC2086
kill $a 2>/dev/null   # only the pids of the tree started above
wait 2>/dev/null
