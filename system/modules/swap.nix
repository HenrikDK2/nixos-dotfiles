{ ... }:

{
  # Compressed swap in RAM. When a game plus the desktop outgrow RAM, cold
  # pages are compressed instead of the kernel OOM-killing a process.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };

  # zswap is on by default in the CachyOS kernel; in front of zram it would
  # compress the same pages twice.
  boot.kernelParams = [ "zswap.enabled=0" ];

  # CachyOS's value with zram: prefer compressing cold memory over dropping
  # page cache the game may need again.
  boot.kernel.sysctl."vm.swappiness" = 150;

  # systemd-oomd only acts on cgroups with ManagedOOM* set, and nothing here
  # sets any (systemd.oomd.enable*Slice* are all off). It still wakes every
  # second to check its empty list, so it is off.
  systemd.oomd.enable = false;
}
