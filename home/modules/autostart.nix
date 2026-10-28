{ pkgs, ... }:

{
  xdg.autostart.enable = true;

  xdg.configFile = {
    "autostart/steam.desktop".text = ''
      [Desktop Entry]
      Type=Application
      Name=Steam
      Exec=${pkgs.bash}/bin/bash -c "${pkgs.coreutils}/bin/sleep 3; exec ${pkgs.steam}/bin/steam -silent"
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
      Exec=${pkgs.bash}/bin/bash -c "${pkgs.coreutils}/bin/sleep 3; exec ${pkgs.thunderbird}/bin/thunderbird"
      X-KDE-autostart-after=panel
    '';
  };
}
