{ inputs, ... }:

{
  imports = [
    inputs.plasma-manager.homeModules.plasma-manager

    ./workspace.nix
    ./panels.nix
    ./input.nix
    ./kwin.nix
    ./shortcuts.nix
    ./config.nix
  ];

  programs.plasma = {
    enable = true;
    overrideConfig = true;
  };
}
