{ pkgs, ... }:

{
  home.pointerCursor = {
    enable = true;

    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;

    x11 = {
      enable = true;
      defaultCursor = "left_ptr";
      size = 24;
    };

    gtk.enable = true;
  };
}
