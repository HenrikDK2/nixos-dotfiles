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
      DontCheckDefaultBrowser = true;

      # Block every AI feature (sidebar chatbot, link-preview summaries, smart
      # tab groups, PDF alt text, speech recognition), so no models are
      # downloaded or run. Local translations stay available.
      AIControls = {
        Default.Value = "blocked";
        Translations.Value = "available";
      };

      # New tab page: no sponsored tiles or story feeds to fetch and render.
      FirefoxHome = {
        SponsoredTopSites = false;
        SponsoredStories = false;
        Stories = false;
      };

      # No onboarding, "what's new" or recommendation messages.
      UserMessaging = {
        ExtensionRecommendations = false;
        FeatureRecommendations = false;
        UrlbarInterventions = false;
        SkipOnboarding = true;
        MoreFromMozilla = false;
        WhatsNew = false;
      };

      # Address bar: no sponsored suggestions, and keystrokes are not sent
      # to Mozilla's online suggestion service.
      FirefoxSuggest = {
        SponsoredSuggestions = false;
        OnlineEnabled = false;
      };

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
