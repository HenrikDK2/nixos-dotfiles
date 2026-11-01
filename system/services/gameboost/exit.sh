#!/bin/bash

is_laptop() {
    [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]
}

set_cpu_governor() {
    local cpu governor available epp

    read -r available 2>/dev/null < /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
    available=" $available "

    if [[ $available == *" powersave "* ]]; then
        governor=powersave
    elif [[ $available == *" ondemand "* ]]; then
        governor=ondemand
    elif [[ $available == *" conservative "* ]]; then
        governor=conservative
    else
        return 1
    fi

    if is_laptop; then
        epp=balance_power
    else
        epp=balance_performance
    fi

    # Keep boost enabled
    if [ -f /sys/devices/system/cpu/cpufreq/boost ]; then
        echo 1 > /sys/devices/system/cpu/cpufreq/boost
    fi

    for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
        [ -f "$cpu/scaling_governor" ] &&
            echo "$governor" > "$cpu/scaling_governor" 2>/dev/null

        [ -f "$cpu/energy_performance_preference" ] &&
            echo "$epp" > "$cpu/energy_performance_preference" 2>/dev/null
    done
}

# Restore automatic power management on all GPUs (VGA, 3D, display controllers)
set_gpu_auto() {
    local gpu class

    for gpu in /sys/bus/pci/devices/*; do
        read -r class 2>/dev/null < "$gpu/class" || continue
        case $class in 0x0300* | 0x0302* | 0x0380*) ;; *) continue ;; esac

        # AMD
        [ -f "$gpu/power_dpm_force_performance_level" ] && echo auto > "$gpu/power_dpm_force_performance_level"
        [ -f "$gpu/power/control" ] && echo auto > "$gpu/power/control"
        [ -f "$gpu/pp_power_profile_mode" ] && echo 0 > "$gpu/pp_power_profile_mode"
    done
}

kill_lingering_processes() {
    ! pgrep -x gamescope-wl >/dev/null && pgrep -x gamescopereaper >/dev/null &&
        killall -9 gamescopereaper 2>/dev/null

    [ "$(pgrep -fc '\.exe$')" -eq 1 ] && pgrep -x winedevice.exe >/dev/null &&
        killall -9 winedevice.exe 2>/dev/null
}

restore_sata_power_management() {
    local host
    for host in /sys/class/scsi_host/host*/link_power_management_policy; do
        echo med_power_with_dipm > "$host" 2>/dev/null
    done
}

restore_nvme_power_management() {
    local nvme_dev
    for nvme_dev in /sys/block/nvme*/device; do
        [ -d "$nvme_dev/power" ] || continue
        echo 1000 > "$nvme_dev/power/autosuspend_delay_ms" 2>/dev/null
        echo auto > "$nvme_dev/power/control" 2>/dev/null
    done
}

restore_pcie_power_management() {
    local pci
    for pci in /sys/bus/pci/devices/*/power/control; do
        echo auto > "$pci" 2>/dev/null
    done
    echo default > /sys/module/pcie_aspm/parameters/policy 2>/dev/null
}

clear_ram_cache() {
    killall -q -9 chrome_crashpad 2>/dev/null
    echo 3 > /proc/sys/vm/drop_caches
}

main() {
    if ! is_laptop; then
        restore_sata_power_management
        restore_nvme_power_management
        restore_pcie_power_management
    fi

    set_cpu_governor
    set_gpu_auto
    kill_lingering_processes
    clear_ram_cache
}

main "$@"
