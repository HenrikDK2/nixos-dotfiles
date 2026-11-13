
{ ... }:

{
  programs.plasma = {
    kwin = {
      effects = {
        wobblyWindows.enable = false;
        cube.enable = false;
        slideBack.enable = false;
        fallApart.enable = false;
        blur.enable = true;

        windowOpenClose.animation = "off";
        minimization.animation = "off";
        desktopSwitching.animation = "off";
      };

      edgeBarrier = 0;
      cornerBarrier = false;

      virtualDesktops = {
        number = 4;
        rows = 1;
      };
    };

    session.sessionRestore.restoreOpenApplicationsOnLogin =
      "startWithEmptySession";

    powerdevil = {
      AC.powerProfile = "performance";
      battery.powerProfile = "powerSaving";
    };

    krunner.shortcuts.launch = [];

    window-rules = [
      {
        description = "Allow window tearing";

        match = {
          window-class = {
            value = ".*";
            type = "regex";
          };
        };

        apply = {
          tearing = {
            value = true;
            apply = "force";
          };
        };
      }

      {
        description = "Look launcher modal focus";

        match = {
          window-class = {
            value = "look";
            type = "substring";
          };

          window-types = [ "normal" ];
        };

        apply = {
          fsplevel = {
            value = 4;
            apply = "force";
          };

          fpplevel = {
            value = 4;
            apply = "force";
          };

          above = {
            value = true;
            apply = "force";
          };
        };
      }
    ];
  };
}
