#!/bin/bash
# build.sh SRC_C OUT [CFLAGS...]  -> driver binary for that gameboostd.c
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src=$(realpath "$1"); out=$2; shift 2
flags=("$@"); [ ${#flags[@]} -eq 0 ] && flags=(-O2)
gcc "${flags[@]}" -g -Wall -Wextra -DGBD_SRC="\"$src\"" "$here/driver.c" -o "$out"
