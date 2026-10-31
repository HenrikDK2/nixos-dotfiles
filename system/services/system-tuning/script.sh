#!/bin/bash

function is_laptop() {
    # Check for presence of a battery device
    if [ -d "/sys/class/power_supply/BAT0" ] || [ -d "/sys/class/power_supply/BAT1" ]; then
        return 0  # true: laptop
    else
        return 1  # false: desktop
    fi
}

# Queue a sysctl setting ("key=value"); apply_sysctls writes them all in a
# single sysctl process instead of one fork+exec per key.
SYSCTL_ARGS=()
sc() { SYSCTL_ARGS+=("$1"); }
apply_sysctls() { sysctl -w "${SYSCTL_ARGS[@]}"; }

# Get total memory in KB
total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2}')

# Tiered min_free_kbytes based on total RAM
if [ "$total_memory" -le $((8 * 1024 * 1024)) ]; then        # <= 8  GB
    min_free_kbytes=8192
elif [ "$total_memory" -le $((16 * 1024 * 1024)) ]; then     # <= 16 GB
    min_free_kbytes=16384
elif [ "$total_memory" -le $((32 * 1024 * 1024)) ]; then     # <= 32 GB
    min_free_kbytes=32768
else                                                         # >  32 GB
    min_free_kbytes=65536
fi

# --------------------
# PERFORMANCE TUNING
# --------------------

# Memory Management
sc vm.swappiness=10                    # Reduce swap usage, keeping more processes in RAM for lower latency.
sc vm.compaction_proactiveness=0       # Disable aggressive memory compaction to avoid CPU spikes.
sc vm.min_free_kbytes=$min_free_kbytes # Maintain minimum free memory to prevent out-of-memory stalls.
sc vm.max_map_count=2147483642         # Allow many memory mappings for large applications and databases.
sc vm.zone_reclaim_mode=0              # Avoid reclaiming memory from remote NUMA nodes to reduce latency.
sc vm.page_lock_unfairness=1           # Improve fairness when locking pages, reducing contention.
sc vm.page-cluster=0                   # Minimize readahead to prevent unnecessary I/O and cache pollution.
sc vm.dirty_ratio=10                   # Flush dirty pages more aggressively to avoid long writeback pauses.
sc vm.dirty_background_ratio=5         # Start background flushing earlier to smooth disk I/O.
sc vm.vfs_cache_pressure=50            # Balance filesystem metadata caching to avoid frequent lookups.
sc vm.dirty_writeback_centisecs=1500   # Control writeback interval to smooth out disk I/O.
sc vm.stat_interval=5                  # Less CPU time spent on memory bookkeeping
sc vm.percpu_pagelist_fraction=0       # Reduce memory allocation overhead
sc vm.watermark_scale_factor=1         # Minimize memory watermark calculations

# CPU & Scheduler (Low Power Impact)
sc kernel.sched_min_granularity_ns=1000000      # Fine-tune scheduler granularity for lower latency in interactive tasks.
sc kernel.sched_autogroup_enabled=0             # Disable autogrouping to prevent latency spikes for single-threaded processes.
sc kernel.perf_event_paranoid=2                 # Restrict unprivileged access to performance counters to reduce overhead.
sc kernel.sched_wakeup_granularity_ns=15000000  # Reduce context switching overhead
sc kernel.sched_migration_cost_ns=5000000       # Improve cache locality
sc kernel.sched_child_runs_first=0              # Prevent child processes from interrupting
sc kernel.nmi_watchdog=0                        # Disable NMI watchdog (prevents CPU sleep)
sc kernel.watchdog=0                            # Disable soft lockup detector
sc kernel.hung_task_timeout_secs=0              # Disable hung task detection
sc kernel.numa_balancing=0                      # Disable NUMA balancing (CPU overhead)

# Network Tuning
sc net.ipv4.tcp_fastopen=3                      # Reduce TCP handshake latency by sending data in the first SYN packet.
sc net.ipv4.tcp_slow_start_after_idle=0         # Avoid slow-start after idle to maintain throughput for long-lived connections.
sc net.ipv4.tcp_mtu_probing=1                   # Dynamically discover MTU to prevent fragmentation and improve throughput.
sc net.core.rmem_max=16777216                   # Increase max socket receive buffer for high-throughput applications.
sc net.core.wmem_max=16777216                   # Increase max socket send buffer for high-throughput applications.
sc net.ipv4.tcp_rmem="4096 87380 16777216"      # Set TCP receive buffer min, default, max for efficient data flow.
sc net.ipv4.tcp_wmem="4096 87380 16777216"      # Set TCP send buffer min, default, max for efficient data flow.
sc net.core.netdev_budget=600                   # Improve network interrupt efficiency
sc net.ipv4.tcp_no_metrics_save=1               # Eliminate periodic TCP housekeeping

# Filesystem Optimizations
sc fs.inotify.max_user_instances=1024
sc fs.inotify.max_user_watches=524288
sc fs.file-max=2097152

# Transparent HugePages (THP)
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled      # Use THP on demand to reduce TLB misses for large memory allocations.
echo advise > /sys/kernel/mm/transparent_hugepage/shmem_enabled # Apply THP to shared memory only when advised to reduce unnecessary CPU overhead.
echo never > /sys/kernel/mm/transparent_hugepage/defrag         # Disable THP defragmentation to avoid CPU stalls during memory allocation.

# Zswap
echo zsmalloc > /sys/module/zswap/parameters/zpool  # Choose efficient memory pool for compressed swap.
echo zstd > /sys/module/zswap/parameters/compressor # Use fast compression algorithm to reduce I/O latency.
echo Y > /sys/module/zswap/parameters/enabled       # Enable compressed swap to reduce pressure on physical memory and disk I/O.

# KSM (Kernel Samepage Merging)
echo 0 > /sys/kernel/mm/ksm/run # Disable KSM to avoid CPU overhead if virtual machines are not used.

if is_laptop; then
    sc vm.laptop_mode=1                         # Enable laptop mode for better power management
    sc kernel.timer_migration=1                 # Allow timer migration for better power management
else
    sc vm.laptop_mode=0                         # Disable laptop mode
    sc kernel.timer_migration=0                 # Pin timers to cores (prevents CPU sleep)
fi

# --------------------
# SECURITY HARDENING
# --------------------

# Kernel Security
sc kernel.dmesg_restrict=1               # Restrict dmesg access to root to prevent information leaks.
sc kernel.ftrace_enabled=0               # Disable kernel function tracing to reduce potential leaks.
sc kernel.kptr_restrict=2                # Hide kernel pointers from unprivileged users to protect kernel memory layout.
sc kernel.unprivileged_bpf_disabled=1    # Disable unprivileged BPF programs to reduce attack surface.
sc kernel.kexec_load_disabled=1          # Prevent unauthorized kernel loading.
sc kernel.sysrq=0                        # Disable SysRq key sequences to prevent unsafe commands.
sc fs.suid_dumpable=0                    # Prevent SUID programs from generating core dumps.
sc kernel.core_pattern="|/dev/null"      # Drop all core dumps to prevent sensitive data leakage.

# Network Security
sc net.ipv4.tcp_syncookies=1                     # Enable SYN cookies to mitigate SYN flood attacks.
sc net.ipv4.tcp_timestamps=0                     # Disable TCP timestamps to reduce fingerprinting attack surface.
sc net.ipv4.tcp_rfc1337=1                        # Handle TIME_WAIT sockets safely to prevent reuse attacks.
sc net.ipv4.conf.all.rp_filter=1                 # Enable reverse path filtering to prevent IP spoofing.
sc net.ipv4.conf.default.rp_filter=1
sc net.ipv4.conf.all.send_redirects=0            # Disable ICMP redirects to prevent MITM attacks.
sc net.ipv4.conf.all.accept_redirects=0
sc net.ipv4.conf.default.accept_redirects=0
sc net.ipv4.conf.all.secure_redirects=0
sc net.ipv4.conf.default.secure_redirects=0
sc net.ipv6.conf.all.accept_redirects=0
sc net.ipv6.conf.default.accept_redirects=0
sc net.ipv4.conf.all.accept_source_route=0       # Disable source routing to prevent traffic redirection attacks.
sc net.ipv4.conf.default.accept_source_route=0
sc net.ipv6.conf.all.accept_source_route=0
sc net.ipv6.conf.default.accept_source_route=0
sc net.ipv6.conf.all.accept_ra=0                 # Disable router advertisements to prevent rogue RA attacks.
sc net.ipv6.conf.default.accept_ra=0
sc net.ipv4.icmp_echo_ignore_all=1               # Ignore ICMP echo requests to prevent network scanning.
sc net.ipv6.icmp.echo_ignore_all=1
sc net.ipv4.tcp_dsack=0                          # Disable duplicate selective ACK to reduce fingerprinting attacks.
sc net.ipv4.tcp_fack=0                           # Disable FACK to reduce fingerprinting attacks.
sc net.ipv6.conf.all.disable_ipv6=1              # Disable IPv6 if not needed to reduce attack surface.
sc net.ipv6.conf.default.disable_ipv6=1
sc net.ipv4.icmp_echo_ignore_broadcasts=1        # Ignore broadcast pings to prevent amplification attacks.
sc net.ipv4.icmp_ignore_bogus_error_responses=1  # Ignore malformed ICMP packets to prevent network abuse.

apply_sysctls

###############################
### Future warning to self ####
###############################

# Enable below sysctl network security tweaks to reduce fingerprinting limits
# It reduces download speed on Arma Reforger Workshop, and possibly other services/games
#sysctl -w net.ipv4.tcp_sack=0
#sysctl -w net.ipv4.tcp_window_scaling=0

echo ""
echo "=== Optimization Complete ==="
if is_laptop; then
    echo "Laptop Mode: Balanced performance and power efficiency"
else
    echo "Desktop Mode: Maximum performance optimizations applied"
fi
