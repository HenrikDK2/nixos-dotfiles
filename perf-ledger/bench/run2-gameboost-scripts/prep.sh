#!/bin/bash
# prep.sh SCEN [snap]: reset the fake root (inside the namespace) to the
# scenario's template, or with "snap" to its post-start snapshot.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
if [ "$2" = snap ]; then reset_root "$1" "$B/snap/$1"; else reset_root "$1"; fi
