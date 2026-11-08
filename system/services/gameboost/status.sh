# gameboost-status: is game mode on, for which game, and what GameBoost changed.

flag=${GAMEBOOST_FLAG:-/run/gameboost/running.flag}
state=${GAMEBOOST_STATE:-/run/gameboost/state}

if [[ ! -e $flag ]]; then
    echo "GameBoost: no game running"
    systemctl is-active --quiet gameboost.service 2>/dev/null ||
        echo "  (gameboost.service is not running)"
    exit 0
fi

pid='' since='' appid='' cmd=''
while IFS='=' read -r key value; do
    case $key in
        pid) pid=$value ;;
        since) since=$value ;;
        appid) appid=$value ;;
        cmd) cmd=$value ;;
    esac
done < "$flag"

echo "GameBoost: game mode"
if [[ $since =~ ^[0-9]+$ ]]; then
    echo "  since:    $(date -d "@$since" '+%F %T') ($(((EPOCHSECONDS - since) / 60)) min)"
fi
if [[ $pid =~ ^[0-9]+$ ]]; then
    if [[ -d /proc/$pid ]]; then alive=running; else alive=gone; fi
    echo "  tracking: PID $pid ($alive)"
fi
[[ $appid =~ ^[1-9][0-9]*$ ]] && echo "  steam:    AppId $appid"
[[ -n $cmd ]] && echo "  command:  ${cmd:0:200}"

if systemctl is-active --quiet gameboost-hold.service 2>/dev/null; then
    echo "  power:    performance profile held through power-profiles-daemon"
fi

[[ -f $state ]] || exit 0

# current FILE: the file's value, with the active entry of "[a] b c" lists.
current() {
    local v=''
    read -r v 2>/dev/null < "$1" || { printf 'gone'; return; }
    if [[ $v == *\[*\]* ]]; then
        v=${v#*\[}
        v=${v%%\]*}
    fi
    printf '%s' "$v"
}

# Originals (first entry per file wins), grouped so per-CPU and per-device
# files print once: cpu*/cpufreq/scaling_governor  powersave -> performance (x16)
declare -A seen=() count=() orig=() now=()
order=()
while IFS='=' read -r file value; do
    [[ -n $file && -z ${seen[$file]+x} ]] || continue
    seen[$file]=1
    key=$file
    [[ $key =~ ^/sys/devices/system/cpu/cpu[0-9]+/cpufreq/(.+)$ ]] && key="cpu*/cpufreq/${BASH_REMATCH[1]}"
    [[ $key =~ ^/sys/bus/pci/devices/[^/]+/power/control$ ]] && key='pci */power/control'
    [[ $key =~ ^/sys/class/scsi_host/host[0-9]+/ ]] && key="scsi host*/${file##*/}"
    if [[ -z ${count[$key]+x} ]]; then
        order+=("$key")
        count[$key]=0
        orig[$key]=$value
        now[$key]=$(current "$file")
    fi
    count[$key]=$((count[$key] + 1))
done < "$state"

echo "  changed (original -> now):"
for key in "${order[@]}"; do
    n=${count[$key]}
    if ((n > 1)); then n=" (x$n)"; else n=''; fi
    printf '    %-48s %s -> %s%s\n' "${key#/sys/}" "${orig[$key]}" "${now[$key]}" "$n"
done
