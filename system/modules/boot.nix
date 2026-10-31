
{ config, pkgs, ... }:

{
  boot.kernelPackages = pkgs.linux-cachyos-latest-lto-x86_64-v3;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelModules = [ "ntsync" ];

  # Disable kernel watchdogs
  boot.kernelParams = [
    "debugfs=off"                   # Disable mounting of debugfs (kernel debugging filesystem) for security/hardening
    "vsyscall=none"                 # Disable legacy vsyscall interface; improves security by preventing old syscall mechanisms
    "split_lock_detect=off"         # Disable split-lock detection (avoids performance penalties or crashes on CPUs supporting this feature)
    "libahci.ignore_sss=1"          # Ignore AHCI "Slumber State" support; can help with SATA controller compatibility issues
    "rootflags=noatime"             # Mount the root filesystem with noatime; avoids updating file access timestamps to reduce disk writes
    "rfkill.default_state=1"        # Set wireless device killswitch state to enabled by default (allows radios to start enabled)
    "rfkill.master_switch_mode=2"   # Configure rfkill master switch behavior; mode 2 controls how hardware/software radio blocks interact
    "amdgpu.msi=1"                  # Enable Message Signaled Interrupts (MSI) for AMD GPUs; can improve interrupt handling
    "nvidia.NVreg_EnableMSI=1"      # Enable MSI interrupts for NVIDIA drivers; may improve GPU interrupt performance/stability
    "nowatchdog"                    # Disable kernel watchdog timers
    "nmi_watchdog=0"                # Disable the NMI watchdog (hardware-based kernel lockup detector)
    "module_blacklist=iTCO_wdt"     # Prevent loading Intel TCO watchdog driver module
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
}
