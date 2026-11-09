#!/bin/bash
# cg.sh <mode:jit|interp> <variant> <scen> <N>  -> prints total Ir
mode=$1; v=$2; s=$3; n=$4
out=$(mktemp -p . cg.XXXX)
if [ "$mode" = interp ]; then export QV4_FORCE_INTERPRETER=1; fi
valgrind --tool=callgrind --callgrind-out-file=$out ./build/bench $v $s $n >/dev/null 2>$out.log
grep -o 'Collected : [0-9]*' $out.log | awk '{print $3}'
rm -f $out $out.log
