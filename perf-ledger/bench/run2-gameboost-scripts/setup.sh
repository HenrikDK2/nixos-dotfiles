#!/bin/bash
# Build stubs + runner, scenario templates, and path-rewritten variants.
# usage: setup.sh NAME=CHECKOUT_DIR ...   (e.g. base=../base c1=../c1)
set -e
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
build_tools
for s in "${ALL_SCENS[@]}"; do build_tmpl "$s"; done
for nv in "$@"; do make_variant "${nv%%=*}" "${nv#*=}"; done
echo "setup done: $B"
