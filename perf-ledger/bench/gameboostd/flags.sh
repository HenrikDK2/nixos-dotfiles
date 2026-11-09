#!/bin/bash
# flags.sh SRC [RUNS=10]: build SRC with each flag set on top of an emulation
# of nixpkgs' stdenv hardening, then report binary size, segments, the
# daemon's memory (mem.sh) and callgrind instructions of a `-1` scan and a
# `-n` validation run.
set -eu
source "$(dirname -- "$0")/common.sh"
SRC=$1 RUNS=${2:-10}
ensure_data "$SRC"
# nixpkgs cc-wrapper default hardening (approximation): fortify3,
# stackprotector, pic/pie, strictoverflow, format, relro, bindnow,
# stackclashprotection, zerocallusedregs. Ubuntu's gcc adds -fcf-protection
# by default; nixpkgs does not, so it is turned off.
NIXH="-D_FORTIFY_SOURCE=3 -fstack-protector-strong -fPIE -pie -fno-strict-overflow -Wformat -Wformat-security -Werror=format-security -fstack-clash-protection -fzero-call-used-regs=used-gpr -fcf-protection=none -Wl,-z,relro -Wl,-z,now"
declare -A SETS=(
  [O2]="-O2"
  [Os]="-Os"
  [O3]="-O3"
  [O2_v3]="-O2 -march=x86-64-v3"
  [O2_nosep]="-O2 -Wl,-z,noseparate-code"
  [O2_gc]="-O2 -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,-O1"
  [O2_lto]="-O2 -flto"
  [O2_noplt]="-O2 -fno-plt"
  [Os_nosep]="-Os -Wl,-z,noseparate-code"
)
GAME_RE=$(cat "$DATA/game.re") EXCL_RE=$(cat "$DATA/excl.re")
for k in O2 Os O3 O2_v3 O2_nosep O2_gc O2_lto O2_noplt Os_nosep; do
  bin=$OUT/gbd_$k
  # shellcheck disable=SC2086
  $CC ${SETS[$k]} -s -Wall $NIXH "$SRC" -o "$bin"
  sz=$(stat -c %s "$bin")
  read -r text data bss _ < <(size "$bin" | tail -1)
  loads=$(readelf -lW "$bin" | grep -c ' LOAD ')
  ir1=$(cg_ir "$OUT/cg_flags_1" - "$bin" -m "$GAME_RE" -x "$EXCL_RE" -1)
  irn=$(cg_ir "$OUT/cg_flags_n" - "$bin" -n -m "$GAME_RE" -x "$EXCL_RE")
  echo "$k: file $sz text $text data $data bss $bss LOADs $loads | Ir(-1 run) $ir1 Ir(-n run) $irn | $("$BENCH/mem.sh" "$bin" "$RUNS")"
done
