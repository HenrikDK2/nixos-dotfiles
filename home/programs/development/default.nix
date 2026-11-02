{ pkgs, ... }:

{
  home.packages = with pkgs; [
    zed-editor
    nodejs_latest
  ];
}
