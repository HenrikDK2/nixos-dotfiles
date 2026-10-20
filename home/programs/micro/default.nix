{ pkgs, ... }:

{
  home.packages = [ pkgs.micro ];

  xdg.configFile."micro" = {
    source = ./.config/micro;
    recursive = true;
  };
}
