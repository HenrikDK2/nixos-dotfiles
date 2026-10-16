{ ... }:

let
  addonUrl = name:
    "https://addons.mozilla.org/firefox/downloads/latest/${name}/latest.xpi";
in
{
  programs.firefox = {
    enable = true;

    policies = {
      AppAutoUpdate = false;
      BackgroundAppUpdate = false;

      DisableFirefoxStudies = true;
      DisableFirefoxScreenshots = true;
      DisableForgetButton = true;
      DisableMasterPasswordCreation = true;
      DisableProfileImport = true;
      DisableProfileRefresh = true;
      DisableSetDesktopBackground = true;
      DisablePocket = true;
      DisableTelemetry = true;
      DisableFormHistory = true;
      DisablePasswordReveal = true;

      BlockAboutConfig = false;

      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          install_url = addonUrl "ublock-origin";
          installation_mode = "force_installed";
          private_browsing = true;
        };

        "jid1-ZAdIEUB7XOzOJw@jetpack" = {
          install_url = addonUrl "duckduckgo-for-firefox";
          installation_mode = "force_installed";
          private_browsing = true;
        };

        "{74145f27-f039-47ce-a470-a662b129930a}" = {
          install_url = addonUrl "clearurls";
          installation_mode = "force_installed";
          private_browsing = true;
        };
      };
    };

    profiles.default = {
      id = 0;
      name = "default";
      isDefault = true;

      settings = {
        "browser.startup.homepage" = "https://duckduckgo.com";
      };
    };
  };
}
