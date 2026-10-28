{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wl-clipboard
    p7zip
  ];
}
