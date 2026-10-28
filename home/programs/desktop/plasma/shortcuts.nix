{ lib, ... }:

let
  nums = map toString (lib.range 1 9);

  bind = name: key:
    lib.listToAttrs (
      map (n: lib.nameValuePair (name n) (key n)) nums
    );

  # KDE doesn't recognize Shift + number keys on a Nordic keyboard.
  windowToDesktopKeys = {
    "1" = "!";
    "2" = "\"";
    "3" = "#";
    "4" = "¤";
    "5" = "%";
    "6" = "&";
    "7" = "/";
    "8" = "(";
    "9" = ")";
  };
in
{
  programs.plasma.shortcuts = {
    kwin =
      bind (n: "Switch to Desktop ${n}") (n: "Meta+${n}")
      // lib.mapAttrs'
        (n: k: lib.nameValuePair "Window to Desktop ${n}" "Meta+${k}")
        windowToDesktopKeys
      // {
        "Window Close" = [ "Meta+D" "Alt+F4" ];
        "Show Desktop" = [];

        "Window Quick Tile Left" = [];
        "Window Quick Tile Right" = [];
        "Window Quick Tile Top" = [];
        "Window Quick Tile Bottom" = [];

        "Window Quick Tile Top Left" = [];
        "Window Quick Tile Top Right" = [];
        "Window Quick Tile Bottom Left" = [];
        "Window Quick Tile Bottom Right" = [];

        "Window to Next Screen" = [];
        "Window to Previous Screen" = [];
      };

    plasmashell =
      bind (n: "activate task manager entry ${n}") (_: [])
      // {
        "activate application launcher" = "Alt+F1";
      };

    ksmserver."Log Out" = "Meta+Escape";
    "services/org.kde.konsole.desktop"._launch = "Meta+Return";
    "services/org.kde.plasma-systemmonitor.desktop"._launch =
      "Ctrl+Alt+Delete";
    "services/lookapp.desktop"._launch = "Meta+Space";
  };
}
