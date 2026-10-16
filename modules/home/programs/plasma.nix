{ inputs, lib, ... }:

let
  nums = map toString (lib.range 1 9);
  # { "<name n>" = <key n>; } for n = 1..9
  bind = name: key:
    lib.listToAttrs (map (n: lib.nameValuePair (name n) (key n)) nums);

  minimizeWindow = app: {
    description = "Start ${app} minimized";

    match = {
      window-class = {
        value = app;
        type = "substring";
      };
      window-types = [ "normal" ];
    };

    apply = {
      minimize = {
        value = true;
        apply = "initially";
      };
    };
  };
in
{
  imports = [ inputs.plasma-manager.homeModules.plasma-manager ];

  # Disable Discover notifier daemon
  xdg.configFile."autostart/org.kde.discover.notifier.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Discover Notifier
    Hidden=true
  '';

  programs.plasma = {
    enable = true;

    workspace = {
      lookAndFeel = "org.kde.breezedark.desktop";
      colorScheme = "BreezeDark";

      wallpaperSlideShow = {
        path = "${inputs.self.outPath}/modules/home/Wallpapers";
        interval = 1200;
      };
    };

    panels = [{
      location = "left";
      height = 56;
      widgets = [
        "org.kde.plasma.kickoff"
        "org.kde.plasma.icontasks"
        "org.kde.plasma.marginsseparator"
        {
          # Enabled tray applets; clipboard is deliberately left out
          systemTray.items.extra = [
            "org.kde.plasma.devicenotifier"
            "org.kde.plasma.mediacontroller"
            "org.kde.plasma.networkmanagement"
            "org.kde.plasma.notifications"
            "org.kde.plasma.volume"
            "org.kde.plasma.battery"
            "org.kde.plasma.bluetooth"
          ];
        }
        {
          digitalClock = {
            time.format = "24h";
            date.enable = false;
            calendar = { firstDayOfWeek = "monday"; plugins = [ ]; };
          };
        }
      ];
    }];

    input.mice = [{
      name = "Logitech USB Receiver";
      vendorId = "046d";
      productId = "c54d";
      accelerationProfile = "none";
    }];

    kwin = {
      effects = {
        wobblyWindows.enable = false;
        cube.enable = false;
        slideBack.enable = false;
        fallApart.enable = false;
        blur.enable = true;# Required for Konsole's blurred background.

        windowOpenClose.animation = "off";
        minimization.animation = "off";
        desktopSwitching.animation = "off";
      };
      edgeBarrier = 0;
      cornerBarrier = false;
      virtualDesktops = { number = 4; rows = 1; };
    };

    session.sessionRestore.restoreOpenApplicationsOnLogin =
      "startWithEmptySession";

    powerdevil = {
      AC.powerProfile = "performance";
      battery.powerProfile = "powerSaving";
    };

    krunner.shortcuts.launch = "Meta+Space";

    shortcuts = {
      kwin = bind (n: "Switch to Desktop ${n}") (n: "Meta+${n}")
        // bind (n: "Window to Desktop ${n}") (n: "Meta+Ctrl+${n}")
        // { "Window Close" = [ "Meta+D" "Alt+F4" ]; "Show Desktop" = [ ]; };

      plasmashell = bind (n: "activate task manager entry ${n}") (_: [ ])
        // { "activate application launcher" = "Alt+F1"; };

      ksmserver."Log Out" = "Meta+Escape";
      "services/org.kde.konsole.desktop"._launch = "Meta+Return";
      "services/org.kde.plasma-systemmonitor.desktop"._launch = "Ctrl+Alt+Delete";
    };

    window-rules = map minimizeWindow [
      "discord"
      "steam"
      "thunderbird"
    ];

    configFile = {
      # Disable Akonadi-dependent KRunner plugins
      krunnerrc.Plugins = {
        "org.kde.events_runnerEnabled" = false;
        kabccontactsEnabled = false;
      };

      # Don't keep clipboard history
      klipperrc.General = { KeepClipboardContents = false; MaxClipItems = 1; };

      baloofilerc."Basic Settings"."Indexing-Enabled" = false;
      kdeglobals.KDE.AnimationDurationFactor = 0.5;
      kdeglobals.KScreen.ScaleFactor = 1.15;

      kwinrc = {
        ModifierOnlyShortcuts.Meta = "";
        Windows = { FocusPolicy = "FocusFollowsMouse"; DelayFocusInterval = 0; };

        # Allow legacy X11/XWayland applications to listen for mouse buttons.
        Xwayland.XwaylandEavesdropsMouse = true;
      };
    };
  };
}
