{ ... }:

{
  # Disable Discover notifier daemon.
  xdg.configFile."autostart/org.kde.discover.notifier.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Discover Notifier
    Hidden=true
  '';

  xdg.dataFile = {
    "kwin/scripts/mastertile".source =
      ./files/kwin/mastertile;

    "kwin/effects/mastertile_effect".source =
      ./files/kwin/mastertile-effect;
  };

  programs.plasma.configFile = {
    # Disable Akonadi-dependent KRunner plugins.
    krunnerrc.Plugins = {
      "org.kde.events_runnerEnabled" = false;
      kabccontactsEnabled = false;
    };

    # Don't keep clipboard history.
    klipperrc.General = {
      KeepClipboardContents = false;
      MaxClipItems = 1;
    };

    baloofilerc."Basic Settings"."Indexing-Enabled" = false;

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
