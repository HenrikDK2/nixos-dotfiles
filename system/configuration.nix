
{ inputs, helpers, lib, pkgs, ... }:

{
  imports = lib.flatten [
    /etc/nixos/hardware-configuration.nix
    (helpers.importAll ../home/users)
    (helpers.importAll ./services)
    (helpers.importAll ./modules)

  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # Clean up old builds
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Automatic updates
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

  system.stateVersion = "26.05";
}
