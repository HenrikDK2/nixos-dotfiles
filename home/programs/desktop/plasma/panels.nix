{ ... }:

{
  programs.plasma.panels = [
    {
      location = "left";
      height = 56;

      widgets = [
        "org.kde.plasma.kickoff"

        {
          iconTasks.behavior.showTasks = {
            onlyInCurrentActivity = false;
            onlyInCurrentDesktop = false;
            onlyInCurrentScreen = false;
          };
        }

        "org.kde.plasma.marginsseparator"

        {
          systemTray.items = {
            extra = [
              "org.kde.plasma.devicenotifier"
              "org.kde.plasma.mediacontroller"
              "org.kde.plasma.networkmanagement"
              "org.kde.plasma.notifications"
              "org.kde.plasma.volume"
              "org.kde.plasma.battery"
              "org.kde.plasma.bluetooth"
            ];

            hidden = [
              "org.kde.plasma.browserintegration"
            ];
          };
        }

        {
          digitalClock = {
            time.format = "24h";
            date.enable = false;

            calendar = {
              firstDayOfWeek = "monday";
              plugins = [];
            };
          };
        }
      ];
    }
  ];
}
