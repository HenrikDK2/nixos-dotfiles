
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
      "https://cachyos-v3-kernel.cachix.org"
      "https://nyx-cache.chaotic.cx/"
    ];

    extra-trusted-public-keys = [
      "cachyos-v3-kernel.cachix.org-1:Vi+DpCa8H/rJPK+D2O3n5Dpz3zpRkCJ1Zs22gejZlj0="
      "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
    ];
  };

  # Garbage collection
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Automatic system upgrades
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    dates = "daily";

    flags = [
      "--update-input"
      "nixpkgs"
      "--no-write-lock-file"
      "-L"
    ];
  };

  system.stateVersion = "26.11";
}
