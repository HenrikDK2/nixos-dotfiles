{ inputs, helpers, lib, ... }:

{
  imports = lib.flatten [
    /etc/nixos/hardware-configuration.nix
    (helpers.importAll ../home/users)
    (helpers.importAll ./services)
    (helpers.importAll ./modules)
  ];

  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

    # Maximum available build parallelism
    max-jobs = "auto";
    cores = 0;

    # Binary cache
    extra-substituters = [
      "https://nixos-x86-64-v3-repo.cachix.org"
    ];

    extra-trusted-public-keys = [
      "nixos-x86-64-v3-repo.cachix.org-1:5cNXpGpvFb1eY+WXd9Sm8wdBlU84lhyy8AWI5F1ySJs="
    ];
  };

  # Garbage collection
  # Weekly in effect: checked daily, and run once the last run is a week old
  # and no game is active (gameboost/maintenance.nix).
  nix.gc = {
    automatic = true;
    dates = "daily";
    options = "--delete-older-than 14d";
  };

  # Unattended Nix work (auto-upgrade, GC, store optimise) runs in an
  # idle-priority slice so it only uses CPU that the desktop are not using.
  systemd.slices.background = {
    description = "Idle-priority background maintenance";
    sliceConfig.CPUWeight = "idle";
  };

  systemd.services.nix-gc.serviceConfig = {
    Slice = "background.slice";
    IOSchedulingClass = "idle";
  };

  # Deduplicate the store in a background run right after each weekly GC
  # (so it never hashes paths the GC is about to delete), not during every
  # build and download (auto-optimise-store). No timer of its own: the
  # nix-optimise unit exists whenever Nix is enabled.
  nix.optimise.automatic = false;
  systemd.services.nix-gc.unitConfig.OnSuccess = [ "nix-optimise.service" ];

  systemd.services.nix-optimise.serviceConfig.Slice = "background.slice";

  system.stateVersion = "26.11";
}
