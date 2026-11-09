#!/bin/bash
# Shared definitions for the GameBoost script harness. Source it.
# Layout (all under $W = parent of this bench dir):
#   build/bin        stub binaries (systemctl, busctl, renice, ...) -> stub
#   build/tmpl/SCEN  pristine fake roots (proc/ sys/ run/) + resp/ (canned replies)
#   build/var/NAME/MODE/{start.sh,exit.sh}  path-rewritten scripts of a checkout
#   root/            the live fake root every run uses (reset before each run)

BENCH=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
W=${BENCH%/*}
B=$W/build
# The fake root lives in $W/root but is bind-mounted on /srv in a private
# mount namespace (in_ns), so rewritten paths are short like the real ones
# (/srv/sys/... instead of a 100-character prefix).
R=/srv
ROOT_DIR=${GB_ROOT_DIR:-$W/root}

# in_ns "$0" "$@": re-exec the calling script in a private mount namespace
# with $ROOT_DIR on /srv. Nothing outside the namespace is touched.
in_ns() {
    [ -n "$GB_NS" ] && return 0
    mkdir -p "$ROOT_DIR"
    GB_NS=1 exec unshare -m --propagation private bash -c \
        'mount --bind "$1" /srv && shift && exec "$@"' _ "$ROOT_DIR" bash "$@"
}
STUBS=(systemctl busctl renice ionice chrt systemd-ac-power pgrep killall notify-send loginctl setpriv)

build_tools() {
    mkdir -p "$B/bin"
    gcc -O2 -Wall -Wextra -o "$B/stub" "$BENCH/stub.c"
    gcc -O2 -Wall -Wextra -o "$B/abrun" "$BENCH/abrun.c"
    local s
    for s in "${STUBS[@]}"; do ln -sf ../stub "$B/bin/$s"; done
}

# resp_line FILE ARGS EXIT OUTPUT
resp() { printf '%s\t%s\t%s\n' "$2" "$3" "$4" >> "$RESP/$1"; }

# Scenario definitions: genroot flags + canned replies.
#   ppd=0/1 driver=amd_pstate|intel_pstate cups="active active" ac=0/1 pg=...
scen_flags() {
    case $1 in
        desk-sysfs | desk-ppd | desk-nocups | desk-x3d | desk-pp | exit-noflag | exit-reaper | exit-wine2 | exit-deferred | exit-deferred-off) echo "" ;;
        lap-bat | lap-ac) echo "--laptop" ;;
        small) echo "--nproc 120 --ncpu 8 --npci 16 --game-threads 30" ;;
        nochildren) echo "--no-children" ;;
        big) echo "--nproc 1000 --game-threads 400" ;;
    esac
    case $1 in desk-x3d) echo "--x3d" ;; desk-pp) echo "--powerplay" ;; esac
}

scen_resp() {
    local s=$1
    RESP=$B/tmpl/$s/resp
    rm -rf "$RESP"; mkdir -p "$RESP"
    case $s in
        desk-ppd | lap-ac) resp systemctl "is-active --quiet power-profiles-daemon.service" 0 "" ;;
        *) resp systemctl "is-active --quiet power-profiles-daemon.service" 3 "" ;;
    esac
    case $s in
        desk-nocups) resp systemctl "is-active cups.socket cups.service" 3 'inactive\ninactive\n' ;;
        lap-ac) resp systemctl "is-active cups.socket cups.service" 3 'active\ninactive\n' ;;
        *) resp systemctl "is-active cups.socket cups.service" 0 'active\nactive\n' ;;
    esac
    case $s in
        exit-deferred-off) resp systemctl "is-active --quiet gameboost.service" 3 "" ;;
        *) resp systemctl "is-active --quiet gameboost.service" 0 "" ;;
    esac
    case $s in
        lap-ac) resp busctl "*" 0 's "intel_pstate"\n' ;;
        *) resp busctl "*" 0 's "amd_pstate"\n' ;;
    esac
    case $s in
        lap-bat) resp systemd-ac-power "*" 1 "" ;;
        *) resp systemd-ac-power "*" 0 "" ;;
    esac
    case $s in
        exit-reaper) resp pgrep "-lx gamescope-wl|gamescopereaper|winedevice.exe" 0 '7001 gamescopereaper\n' ;;
        exit-wine2) resp pgrep "-lx gamescope-wl|gamescopereaper|winedevice.exe" 0 '5004 winedevice.exe\n'
                    resp pgrep "-fc \.exe\$" 0 '2\n' ;;
        *) resp pgrep "-lx gamescope-wl|gamescopereaper|winedevice.exe" 0 '5004 winedevice.exe\n'
           resp pgrep "-fc \.exe\$" 0 '1\n' ;;
    esac
}

ALL_SCENS=(nochildren big desk-sysfs desk-ppd desk-nocups desk-x3d desk-pp lap-bat lap-ac small exit-reaper exit-wine2 exit-deferred exit-deferred-off exit-noflag)

build_tmpl() {
    local s=$1
    rm -rf "$B/tmpl/$s/fs"; mkdir -p "$B/tmpl/$s/fs"
    # shellcheck disable=SC2046
    python3 "$BENCH/genroot.py" "$B/tmpl/$s/fs" $(scen_flags "$s")
    case $s in
        exit-deferred | exit-deferred-off) : > "$B/tmpl/$s/fs/run/nixos-upgrade.deferred" ;;
    esac
    scen_resp "$s"
}

# make_variant NAME CHECKOUT: path-rewritten copies of start.sh/exit.sh in
# modes "start" (FOLLOW_UP=() : only the game-start path) and "full"
# (FOLLOW_UP=(0 boost 0 render 0 boost), RENDER_SAMPLE_S=0).
make_variant() {
    local name=$1 src=$2/system/services/gameboost/scripts mode d
    for mode in start full render; do
        d=$B/var/$name/$mode
        mkdir -p "$d"
        for f in start.sh exit.sh; do
            sed -e "s#/proc/#$R/proc/#g" -e "s#/sys/#$R/sys/#g" -e "s#/run/#$R/run/#g" \
                "$src/$f" > "$d/$f"
        done
        case $mode in
            start) sed -i 's/^FOLLOW_UP=([^)]*)/FOLLOW_UP=()/' "$d/start.sh" ;;
            full) sed -i -e 's/^FOLLOW_UP=([^)]*)/FOLLOW_UP=(0 boost 0 render 0 boost)/' \
                -e 's/^RENDER_SAMPLE_S=3$/RENDER_SAMPLE_S=0/' "$d/start.sh" ;;
            render) sed -i -e 's/^FOLLOW_UP=([^)]*)/FOLLOW_UP=(0 render)/' \
                -e 's/^RENDER_SAMPLE_S=3$/RENDER_SAMPLE_S=1/' "$d/start.sh" ;;
        esac
        grep -q "$R/proc/" "$d/start.sh" || { echo "rewrite failed: $d" >&2; return 1; }
        case $mode in
            start) grep -q '^FOLLOW_UP=() ' "$d/start.sh" ;;
            full) grep -q '^RENDER_SAMPLE_S=0$' "$d/start.sh" && grep -q '^FOLLOW_UP=(0 boost' "$d/start.sh" ;;
            render) grep -q '^RENDER_SAMPLE_S=1$' "$d/start.sh" ;;
        esac || { echo "mode sed failed: $d" >&2; return 1; }
        chmod +x "$d"/*.sh
    done
}

# Environment for a run of scenario $1.
run_env() {
    export PATH=$B/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    export GB_LOG=$R/cmd.log GB_RESP=$B/tmpl/$1/resp LC_ALL=C
}

# reset_root SCEN [STATEFROM]: fresh copy of the scenario's tree in $R. With
# STATEFROM (a saved post-start snapshot dir), that snapshot instead.
reset_root() {
    [ "$GB_NS" = 1 ] && mountpoint -q "$R" || { echo "not in namespace" >&2; exit 1; }
    local src=${2:-$B/tmpl/$1/fs} d
    # proc/ is large and only written by the render step (timerslack_ns):
    # recopied when the source changes or GB_RESET_PROC=1.
    if [ "$GB_RESET_PROC" = 1 ] || [ "$(cat "$R/.src" 2>/dev/null)" != "$src" ]; then
        rm -rf "${R:?}"/* "$R"/.stamp "$R"/.src
        cp -a "$src"/. "$R"/
        printf '%s\n' "$src" > "$R/.src"
    else
        for d in sys run; do rm -rf "${R:?}/$d"; cp -a "$src/$d" "$R/$d"; done
        rm -f "$R"/cmd.log "$R"/.out "$R"/.err
    fi
    : > "$R/cmd.log"
    touch "$R/.stamp"
}

# dump_root: every regular file under $R/sys and $R/run with its content, and
# the command log, with $R replaced by ROOT. For byte comparison.
dump_root() {
    (cd "$R" && { find sys run -type f; find proc -type f -newer "$R/.stamp"; } 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
        printf '== %s\n' "$f"; cat -- "$f"; done
     printf '== cmd.log\n'; cat "$R/cmd.log"
     printf '== state listing\n'; ls -A "$R/run" "$R/run/gameboost" 2>&1) | sed "s#$R#ROOT#g"
}

GAME_PIDS=(5000 5010)

# snapshot SCEN: post-start.sh tree of the base variant (input for exit.sh
# runs), in $B/snap/SCEN. running.flag removed, as gameboostd does before
# exit.sh. exit-noflag: no state file at all (start.sh never ran).
snapshot() {
    local s=$1
    reset_root "$s"
    if [ "$s" != exit-noflag ]; then
        "$B/var/base/start/start.sh" "${GAME_PIDS[@]}" > /dev/null 2>&1
    fi
    rm -f "$R/run/gameboost/running.flag"
    : > "$R/cmd.log"
    rm -rf "$B/snap/$s"; mkdir -p "$B/snap/$s"
    cp -a "$R"/. "$B/snap/$s"/
}
