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

    imports = lib.flatten [
      (helpers.importAll ../services)
      (helpers.importAll ../programs)
    ];

    home.packages = with pkgs; [
      wl-clipboard
      p7zip
      mpv

      zed-editor
      discord

      gamescope
      proton-cachyos-x86_64-v3
      protontricks
      protonplus
    ];

    # Auto start minimized
    xdg.autostart.enable = true;
    xdg.configFile = {
      "autostart/steam.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Steam
        Exec=${pkgs.steam}/bin/steam -silent
        X-KDE-autostart-after=panel
      '';

      "autostart/discord.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Discord
        Exec=${pkgs.bash}/bin/bash -c "${pkgs.coreutils}/bin/sleep 3; exec ${pkgs.discord}/bin/discord --start-minimized"
        X-KDE-autostart-after=panel
      '';

      "autostart/thunderbird.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=Thunderbird
        Exec=${pkgs.thunderbird}/bin/thunderbird
        X-KDE-autostart-after=panel
      '';
    };
  };
}
