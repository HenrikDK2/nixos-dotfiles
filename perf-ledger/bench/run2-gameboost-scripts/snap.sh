#!/bin/bash
# snap.sh SCEN...: build post-start snapshots (base start.sh) for exit.sh runs.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
in_ns "$0" "$@"
run_env x
for s; do run_env "$s"; GB_RESET_PROC=1 snapshot "$s"; done
