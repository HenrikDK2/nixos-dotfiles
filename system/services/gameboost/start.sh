#!/bin/bash

# Original values, restored by exit.sh.
STATE=/run/gameboost/state
FLAG=/run/gameboost/running.flag

# Files whose original value is already in $STATE. Kept in memory so the
# "saved yet?" check is a hash lookup instead of a grep fork per sysfs file
# (hundreds per game launch). Seeded from an existing $STATE so originals
# left by an interrupted run are never overwritten.
declare -A SAVED=()

load_saved() {
    local f _
    [ -f "$STATE" ] || return 0
    while IFS='=' read -r f _; do
        [ -n "$f" ] && SAVED[$f]=1   # empty subscript would abort main
    done < "$STATE"
}

# is_saved FILE: true if FILE's original is in $STATE. If $STATE was removed
# meanwhile (exit.sh of a previous game), nothing counts as saved any more.
is_saved() {
    [ -f "$STATE" ] || SAVED=()
    [[ -n ${SAVED[$1]+x} ]]
}

# save_original FILE VALUE: record FILE's original VALUE once.
save_original() {
    is_saved "$1" && return 0
    printf '%s=%s\n' "$1" "$2" >> "$STATE"
    SAVED[$1]=1
}

# set_saved FILE VALUE: save FILE's original once, then write VALUE.
# Returns 1 if FILE isn't writable.
set_saved() {
    local cur
    [ -w "$1" ] || return 1

    if ! is_saved "$1"; then
        read -r cur < "$1" 2>/dev/null
        if [[ $cur == *\[*\]* ]]; then
            cur=${cur#*\[}
            cur=${cur%%\]*}
        fi
        save_original "$1" "$cur"
    fi

    echo "$2" > "$1" 2>/dev/null
}

is_laptop() {
    [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]
}

set_cpu_performance() {
    local cpu f

    # Boost: acpi-cpufreq (global), amd-pstate (per CPU), intel_pstate.
    for f in /sys/devices/system/cpu/cpufreq/boost /sys/devices/system/cpu/cpu*/cpufreq/boost; do
        set_saved "$f" 1
    done
    set_saved /sys/devices/system/cpu/intel_pstate/no_turbo 0

    for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
        # EPP first: amd-pstate rejects EPP writes under "performance".
        set_saved "$cpu/energy_performance_preference" performance
        set_saved "$cpu/scaling_governor" performance
    done

    # No split-lock slowdown (Intel).
    set_saved /proc/sys/kernel/split_lock_mitigate 0

    # Dual-CCD X3D: prefer the V-Cache CCD (BIOS CPPC = "Driver").
    for f in /sys/bus/platform/drivers/amd_x3d_vcache/*/amd_x3d_mode; do
        set_saved "$f" cache
    done
}

# try_write FILE VALUE: write VALUE to a sysfs file; fails if the kernel
# rejects it.
try_write() {
    echo "$2" > "$1" 2>/dev/null
}

# profile_indices FILE: set idx to the first field of the first line naming
# 3D_FULL_SCREEN and cur to that of the first line containing '*' (the active
# profile). Same result as awk '/RE/ {print $1; exit}', without two forks.
profile_indices() {
    local line
    idx= cur=
    while IFS= read -r line || [ -n "$line" ]; do
        [[ -z $idx && $line == *3D_FULL_SCREEN* ]] && read -r idx _ <<< "$line"
        [[ -z $cur && $line == *\** ]] && read -r cur _ <<< "$line"
        [[ -n $idx && -n $cur ]] && break
    done 2>/dev/null < "$1"
}

# Force performance mode on all GPUs (VGA, 3D, display controllers)
set_gpu_performance() {
    local gpu class prof idx cur

    for gpu in /sys/bus/pci/devices/*; do
        read -r class 2>/dev/null < "$gpu/class" || continue
        case $class in 0x0300* | 0x0302* | 0x0380*) ;; *) continue ;; esac

        set_saved "$gpu/power/control" on

        # AMD: 3D_FULL_SCREEN by name; save the active (*) row's index.
        prof=$gpu/pp_power_profile_mode
        [ -w "$prof" ] || continue
        profile_indices "$prof"
        [ -n "$idx" ] || continue

        # swsmu GPUs (Navi/RDNA dGPUs, Renoir, Van Gogh) accept a profile in
        # "auto", which keeps the driver's own workload switching; "manual"
        # would turn that off. powerplay GPUs (Polaris/Tonga/Fiji, Vega10/20,
        # Raven/Picasso APUs) reject it unless the level is "manual", so fall
        # back to that only when the first write fails. The original is saved
        # before any write, so an interrupted start.sh never leaves a profile
        # that exit.sh cannot undo.
        [ -n "$cur" ] && save_original "$prof" "$cur"
        try_write "$prof" "$idx" && continue
        set_saved "$gpu/power_dpm_force_performance_level" manual || continue
        # Record the profile again after the level: exit.sh restores newest
        # first, so it puts the profile back while the level is still manual.
        [ -n "$cur" ] && printf '%s=%s\n' "$prof" "$cur" >> "$STATE"
        try_write "$prof" "$idx"
    done
}

disable_sata_power_management() {
    local host
    for host in /sys/class/scsi_host/host*/link_power_management_policy; do
        set_saved "$host" max_performance
    done
}

disable_nvme_power_management() {
    local nvme_dev
    for nvme_dev in /sys/block/nvme*/device; do
        [ -d "$nvme_dev/power" ] || continue
        set_saved "$nvme_dev/power/autosuspend_delay_ms" -1
        set_saved "$nvme_dev/power/control" on
    done
}

disable_pcie_power_management() {
    local pci
    for pci in /sys/bus/pci/devices/*/power/control; do
        set_saved "$pci" on
    done
    set_saved /sys/module/pcie_aspm/parameters/policy performance
}

# tree_pids ROOT...: ROOT and every live descendant, in TREE. A game is often
# forked well after detection by a process that is not itself a match (Steam's
# pv-adverb/srt-bwrap, Proton's python script), and nice is only inherited at
# fork, so boosting just the matched PIDs can miss the game entirely.
# ppid map from /proc/PID/stat; comm may contain spaces or ')', so the fields
# are parsed after the last ')'.
tree_pids() {
    local stat line rest pid ppid i
    local -A kids=()
    TREE=()

    for stat in /proc/[0-9]*/stat; do
        read -r line 2>/dev/null < "$stat" || continue
        rest=${line##*) }
        read -r _ ppid _ <<< "$rest"
        pid=${stat#/proc/}
        kids[$ppid]+=" ${pid%/stat}"
    done

    for pid; do [ -d "/proc/$pid" ] && TREE+=("$pid"); done
    for ((i = 0; i < ${#TREE[@]}; i++)); do
        for pid in ${kids[${TREE[i]}]}; do TREE+=("$pid"); done
    done
}

# cgroups already handled (weight set, or warned once that it can't be).
declare -A CG_DONE=()

set_process_priority() {
    local pid t cg line comm tids=()
    local -A seen=()

    for pid; do
        [[ -n ${seen[$pid]+x} ]] && continue
        seen[$pid]=1
        [ -d "/proc/$pid/task" ] || continue

        # wineserver sets its own priority at startup and was never boosted.
        read -r comm 2>/dev/null < "/proc/$pid/comm"
        [[ $comm == wineserver ]] && continue

        # Nice is per thread: include every existing thread.
        for t in /proc/"$pid"/task/*; do
            tids+=("${t##*/}")
        done

        # Nice only applies within a cgroup; raise the cgroup's weight.
        # cgroup v2 entry ("0::/path"); read with builtins, no sed fork.
        cg=
        while IFS= read -r line || [ -n "$line" ]; do
            [[ $line == 0::* ]] && { cg=${line#0::}; break; }
        done 2>/dev/null < "/proc/$pid/cgroup"
        # cpu.weight only exists where systemd enabled the cpu controller.
        if [ -n "$cg" ] && [ -z "${CG_DONE[$cg]+x}" ]; then
            CG_DONE[$cg]=1
            set_saved "/sys/fs/cgroup$cg/cpu.weight" 1000 ||
                echo "gameboost: could not set cpu.weight in $cg (cpu controller off?); CPU weight boost skipped" >&2
        fi
    done

    [ ${#tids[@]} -gt 0 ] || return

    renice -n -11 -p "${tids[@]}" >/dev/null 2>&1
    ionice -c2 -n0 -p "${tids[@]}" >/dev/null 2>&1 && return

    # ionice stops at the first vanished thread: retry one by one
    for t in "${tids[@]}"; do
        ionice -c2 -n0 -p "$t" >/dev/null 2>&1
    done
}

# boost_tree ROOT...: priorities for the game PIDs and all their descendants.
boost_tree() {
    tree_pids "$@"
    set_process_priority "${TREE[@]}"
}

# Processes the game starts after detection (Proton starting the .exe, a
# launcher starting the game) are covered by running the priority step again.
# Runs in the foreground: gameboostd SIGTERMs start.sh when game mode ends.
REBOOST_AFTER=(10 50)   # seconds: at +10 s and +60 s

follow_up() {
    local delay
    for delay in "${REBOOST_AFTER[@]}"; do
        sleep "$delay"
        [ -f "$FLAG" ] || return
        boost_tree "$@"
    done
}

main() {
    mkdir -p "${STATE%/*}"
    load_saved

    boost_tree "$@"

    if ! is_laptop; then
        disable_sata_power_management
        disable_nvme_power_management
        disable_pcie_power_management
    fi

    set_cpu_performance
    set_gpu_performance

    follow_up "$@"
}

main "$@"
