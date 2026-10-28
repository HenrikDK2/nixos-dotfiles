{ pkgs, ... }:

{
  home.packages = with pkgs; [
    gamescope
    proton-cachyos-x86_64-v3
    protontricks
    protonplus
  ];
}
