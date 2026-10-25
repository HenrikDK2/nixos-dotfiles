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

  # Automatic system upgrades
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    dates = "daily";

    flags = [
      "--update-input"
      "nixpkgs"
      "--no-write-lock-file"
      "--impure"
      "-L"
    ];
  };

  system.stateVersion = "26.11";
}
