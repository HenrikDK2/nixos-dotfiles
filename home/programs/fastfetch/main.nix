{ pkgs, ... }:

{
  home.packages = [ pkgs.fastfetch ];
  xdg.configFile."fastfetch".source = .config/fastfetch;
}
