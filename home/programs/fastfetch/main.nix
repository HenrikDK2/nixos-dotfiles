{ pkgs, ... }:

{
  home.packages = [ pkgs.fastfetch pkgs.font-awesome ];
  xdg.configFile."fastfetch".source = .config/fastfetch;
}
