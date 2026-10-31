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

    # Reduce duplicate files in the Nix store
    auto-optimise-store = true;

    # Binary cache
    extra-substituters = [
      "https://nixos-x86-64-v3-repo.cachix.org"
    ];

    extra-trusted-public-keys = [
      "nixos-x86-64-v3-repo.cachix.org-1:5cNXpGpvFb1eY+WXd9Sm8wdBlU84lhyy8AWI5F1ySJs="
    ];
  };

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Unattended Nix work (auto-upgrade, GC) runs in an idle-priority slice so it
  # only uses CPU that the desktop are not using.
  systemd.slices.background = {
    description = "Idle-priority background maintenance";
    sliceConfig.CPUWeight = "idle";
  };

  systemd.services.nix-gc.serviceConfig = {
    Slice = "background.slice";
    IOSchedulingClass = "idle";
  };

  system.stateVersion = "26.11";
}
