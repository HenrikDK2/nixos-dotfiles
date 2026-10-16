
{ config, pkgs, ... }:

{
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Disable kernel watchdogs
  boot.kernelParams = [
    "nowatchdog"
    "nmi_watchdog=0"
  ];

  # Blacklist common Intel hardware watchdog drivers
  boot.blacklistedKernelModules = [
    "iTCO_wdt"
    "iTCO_vendor_support"
  ];

  # Disable systemd watchdog handling
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "0";
    RebootWatchdogSec = "0";
    KExecWatchdogSec = "0";
    WatchdogDevice = "";
  };
}
