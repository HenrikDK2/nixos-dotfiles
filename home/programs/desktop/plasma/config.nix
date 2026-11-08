{ ... }:

{
  xdg.dataFile = {
    "kwin/scripts/mastertile".source =
      ./files/kwin/mastertile;

    "kwin/effects/mastertile_effect".source =
      ./files/kwin/mastertile-effect;
  };

  programs.plasma.configFile = {
    # Disable Akonadi-dependent KRunner plugins, the file search (Baloo
    # indexing is off: it only answers "not supported", but keeps a resident
    # baloorunner process after the first search) and app-store suggestions
    # (no AppStream catalog on NixOS, and Discover is not installed).
    krunnerrc.Plugins = {
      "org.kde.events_runnerEnabled" = false;
      kabccontactsEnabled = false;
      baloosearchEnabled = false;
      krunner_appstreamEnabled = false;
    };

    # kded modules with nothing to do here (KF6 still reads kded5rc):
    # - Flatpak browser integration: Flatpak is off, yet it runs `flatpak
    #   override` for 8 browsers at every login.
    # - Keyboard LED accent colour (off): starts a root HID helper at login.
    # - inotify limit survey: reads every fd of every process every 10 min,
    #   for a "limit low" warning the configured limits never reach.
    kded5rc = {
      Module-browserintegrationflatpakintegrator.autoload = false;
      Module-kameleon.autoload = false;
      Module-inotify.autoload = false;
    };

    # Don't keep clipboard history.
    klipperrc.General = {
      KeepClipboardContents = false;
      MaxClipItems = 1;
    };

    baloofilerc."Basic Settings"."Indexing-Enabled" = false;

    # Don't record opened files and apps (Recent files in the launcher and
    # Dolphin). 2 = remember no applications.
    kactivitymanagerd-pluginsrc."Plugin-org.kde.ActivityManager.Resources.Scoring"."what-to-remember" = 2;

    kdeglobals.KDE.AnimationDurationFactor = 0.5;
    kdeglobals.KScreen.ScaleFactor = 1.15;

    kwinrc = {
      Plugins = {
        mastertileEnabled = true;
        mastertile_effectEnabled = true;
      };

      ModifierOnlyShortcuts.Meta = "";

      Windows = {
        FocusPolicy = "FocusFollowsMouse";
        DelayFocusInterval = 0;
      };

      # Allow legacy X11/XWayland applications to listen for mouse buttons.
      Xwayland.XwaylandEavesdropsMouse = true;
    };
  };
}
