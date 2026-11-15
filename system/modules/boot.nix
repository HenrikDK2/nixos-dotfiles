
{ config, pkgs, lib, helpers, ... }:

{
  boot.kernelPackages = pkgs.linux-cachyos-latest-lto-x86_64-v3;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = [ "ntsync" ];
  boot.loader.systemd-boot.memtest86.enable = true;

  # Disable kernel watchdogs
  boot.kernelParams = [
    "debugfs=off"                   # Disable mounting of debugfs (kernel debugging filesystem) for security/hardening
    "vsyscall=none"                 # Disable legacy vsyscall interface; improves security by preventing old syscall mechanisms
    "split_lock_detect=off"         # Disable split-lock detection (avoids performance penalties or crashes on CPUs supporting this feature)
    "rootflags=noatime"             # Mount the root filesystem with noatime; avoids updating file access timestamps to reduce disk writes
    "rfkill.default_state=1"        # Set wireless device killswitch state to enabled by default (allows radios to start enabled)
    "rfkill.master_switch_mode=2"   # Configure rfkill master switch behavior; mode 2 controls how hardware/software radio blocks interact
    "amdgpu.msi=1"                  # Enable Message Signaled Interrupts (MSI) for AMD GPUs; can improve interrupt handling/stability
    "nvidia.NVreg_EnableMSI=1"      # Enable MSI interrupts for NVIDIA drivers; may improve GPU interrupt performance/stability
    "nowatchdog"                    # Disable kernel watchdog timers
    "nmi_watchdog=0"                # Disable the NMI watchdog (hardware-based kernel lockup detector)
    "module_blacklist=iTCO_wdt"     # Prevent loading Intel TCO watchdog driver module

    # Gaming latency optimizations
    "preempt=full"                  # Request full kernel preemption; may improve scheduling responsiveness, with possible throughput overhead
    "threadirqs"                    # Convert eligible hardware interrupt handlers into schedulable threads; may improve interrupt responsiveness
  ]

  # Desktops only: laptops keep HDMI/DP audio from an AMD GPU, and staggered
  # spin-up handling only matters for desktops with several SATA drives.
  ++ lib.optionals (!helpers.isLaptop) [
    "libahci.ignore_sss=1"          # Ignore the AHCI staggered spin-up flag, so all SATA drives spin up at once (faster boot)
    "amdgpu.audio=0"                # Disable AMD GPU HDMI/DisplayPort audio support
  ];

  # Blacklist common Intel hardware watchdog drivers
  boot.blacklistedKernelModules = [
    "iTCO_wdt"
    "iTCO_vendor_support"
  ];

  # Disable systemd watchdog handling
  systemd.settings.Manager = {
    DefaultTimeoutStopSec = "10s";

    RuntimeWatchdogSec = "0";
    RebootWatchdogSec = "0";
    KExecWatchdogSec = "0";
    WatchdogDevice = "";
  };

  # Desktop CPU performance governor
  # Keeps the CPU governor in performance mode to reduce frequency ramp-up delays.
  # Increases power consumption and heat; may reduce thermal boost headroom.
  powerManagement.cpuFreqGovernor =
    lib.mkIf (!helpers.isLaptop) "performance";

  # Mesa RADV Vulkan optimizations
  environment.sessionVariables = {
    # Enable native Wayland support in Proton where supported.
    PROTON_ENABLE_WAYLAND = "1";

    # Enable Proton's WoW64 mode (64-bit and 32-bit Windows applications).
    PROTON_USE_WOW64 = "1";

    # Force immediate Vulkan presentation through Mesa.
    # Reduces VSync-related presentation latency but allows screen tearing.
    MESA_VK_WSI_PRESENT_MODE = "immediate";
  };
}
