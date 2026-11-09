#!/bin/bash
# patequiv.sh [FILE...]: check that exit.sh's old restore_saved regexes and the
# glob patterns of the exit-restore-glob candidate select the same paths.
# Paths: built-in edge cases plus every path in the given state files.
export LC_ALL=C
pairs=(
    'cpufreq|intel_pstate|amd_x3d_mode|cpu\.weight' '@(*cpufreq*|*intel_pstate*|*amd_x3d_mode*|*cpu.weight*)'
    'pp_power_profile_mode|power_dpm_force_performance_level|^/sys/bus/pci/devices/.*/power/control$' '@(*pp_power_profile_mode*|*power_dpm_force_performance_level*|/sys/bus/pci/devices/*/power/control)'
    'link_power_management_policy' '*link_power_management_policy*'
    '^/sys/block/nvme' '/sys/block/nvme*'
    '^/sys/bus/pci/devices/.*/power/control$|pcie_aspm' '@(/sys/bus/pci/devices/*/power/control|*pcie_aspm*)'
)
paths=(
    /sys/devices/system/cpu/cpufreq/boost /sys/devices/system/cpu/cpu7/cpufreq/boost
    /sys/devices/system/cpu/cpu12/cpufreq/scaling_governor /sys/devices/system/cpu/intel_pstate/no_turbo
    /sys/bus/platform/drivers/amd_x3d_vcache/AMDI0101:00/amd_x3d_mode
    "/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-steam@autostart.service/cpu.weight"
    /sys/fs/cgroup/a/cpuXweight /sys/fs/cgroup/x/cpu.weight.foo /sys/fs/cgroup/cpu.weightless
    /sys/bus/pci/devices/0000:03:00.0/power/control /sys/bus/pci/devices//power/control
    /sys/bus/pci/devices/0000:03:00.0/power/control2 /x/sys/bus/pci/devices/0000:03:00.0/power/control
    /sys/bus/pci/devices/0000:03:00.0/pp_power_profile_mode /sys/bus/pci/devices/0000:03:00.0/power_dpm_force_performance_level
    /sys/class/scsi_host/host0/link_power_management_policy /sys/block/nvme0n1/device/power/control
    /sys/block/nvme0n1/device/power/autosuspend_delay_ms /x/sys/block/nvme0 /sys/block/nvm /sys/block/nvme
    /sys/module/pcie_aspm/parameters/policy '' ' ' '*' '[' 'a]b' '/sys/bus/pci/devices/*/power/control'
    "/sys/fs/cgroup/odd [x] *?/cpu.weight" $'/sys/a\\b/cpufreq' /sys/fs/cgroup/a\|b/cpu.weight
)
for f; do while IFS='=' read -r p _; do paths+=("$p"); done < "$f"; done
n=0 bad=0
for ((k = 0; k < ${#pairs[@]}; k += 2)); do
    re=${pairs[k]} gl=${pairs[k + 1]}
    for p in "${paths[@]}"; do
        r=0 g=0
        [[ $p =~ $re ]] && r=1
        # shellcheck disable=SC2053
        [[ $p == $gl ]] && g=1
        ((n++))
        ((r == g)) || { ((bad++)); echo "MISMATCH re=$re glob=$gl path=$p regex=$r glob=$g"; }
    done
done
echo "patequiv: $n checks, $bad mismatches"
((bad == 0))
