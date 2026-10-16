{ pkgs, lib, helpers, inputs, ... }:

let
  username = "henrik";

  gitUsername = "HenrikDK2";
  gitEmail = "30632653+HenrikDK2@users.noreply.github.com";
in
{
  users.users.${username} = {

    isNormalUser = true;

    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    initialPassword = "1234";
  };

  home-manager.extraSpecialArgs = {
    inherit gitUsername gitEmail;
  };

  home-manager.users.${username} = {
    home.stateVersion = "26.05";

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

    imports = helpers.importAll ../programs;

    home.packages = with pkgs; [
      micro
      wl-clipboard

      zed-editor
      discord

      steam
      faugus-launcher
      protontricks
      protonplus
    ];

    xdg.autostart = {
      enable = true;

      entries = with pkgs; [
        "${steam}/share/applications/steam.desktop"
        "${discord}/share/applications/discord.desktop"
        "${thunderbird}/share/applications/thunderbird.desktop"
      ];
    };
  };
}
