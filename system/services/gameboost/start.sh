#!/bin/bash

is_laptop() {
    [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]
}

set_cpu_performance() {
    local cpu

    # Enable boost
    if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
        echo 1 > /sys/devices/system/cpu/cpufreq/boost
    fi

    for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
        [ -f "$cpu/scaling_governor" ] &&
            echo performance > "$cpu/scaling_governor" 2>/dev/null

        [ -f "$cpu/energy_performance_preference" ] &&
            echo performance > "$cpu/energy_performance_preference" 2>/dev/null
    done
}

# Force performance mode on all GPUs (VGA, 3D, display controllers)
set_gpu_performance() {
    local gpu class

    for gpu in /sys/bus/pci/devices/*; do
        read -r class 2>/dev/null < "$gpu/class" || continue
        case $class in 0x0300* | 0x0302* | 0x0380*) ;; *) continue ;; esac

        # AMD
        [ -f "$gpu/power_dpm_force_performance_level" ] && echo manual > "$gpu/power_dpm_force_performance_level"
        [ -f "$gpu/power/control" ] && echo on > "$gpu/power/control"
        [ -f "$gpu/pp_power_profile_mode" ] && echo 1 > "$gpu/pp_power_profile_mode"
    done
}

kill_background_processes() {
    pkill -9 -f '^(cmst|hypridle|mullvad-gui|blueman-applet|blueman-manager|blueman-tray|chrome_crashpad)( |$)' 2>/dev/null
}

disable_sata_power_management() {
    local host
    for host in /sys/class/scsi_host/host*/link_power_management_policy; do
        echo max_performance > "$host" 2>/dev/null
    done
}

disable_nvme_power_management() {
    local nvme_dev
    for nvme_dev in /sys/block/nvme*/device; do
        [ -d "$nvme_dev/power" ] || continue
        echo -1 > "$nvme_dev/power/autosuspend_delay_ms" 2>/dev/null
        echo on > "$nvme_dev/power/control" 2>/dev/null
    done
}

disable_pcie_power_management() {
    local pci
    for pci in /sys/bus/pci/devices/*/power/control; do
        echo on > "$pci" 2>/dev/null
    done
    echo performance > /sys/module/pcie_aspm/parameters/policy 2>/dev/null
}

clear_ram_cache() {
    pkill -9 -x chrome_crashpad 2>/dev/null
    echo 3 > /proc/sys/vm/drop_caches
}

set_process_priority() {
    local pid alive=()

    for pid; do
        kill -0 "$pid" 2>/dev/null && alive+=("$pid")
    done

    [ ${#alive[@]} -gt 0 ] || return

    renice -n -11 -p "${alive[@]}" >/dev/null 2>&1
    ionice -c2 -n0 -p "${alive[@]}" >/dev/null 2>&1 && return

    # ionice stops at the first PID that vanished: retry one by one
    for pid in "${alive[@]}"; do
        ionice -c2 -n0 -p "$pid" >/dev/null 2>&1
    done
}

main() {
    set_process_priority "$@"

    if ! is_laptop; then
        disable_sata_power_management
        disable_nvme_power_management
        disable_pcie_power_management
    fi

    set_cpu_performance
    set_gpu_performance
    kill_background_processes
    clear_ram_cache
}

main "$@"
