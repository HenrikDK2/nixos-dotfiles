{ ... }:


{
  programs.thunderbird = {
    enable = true;

    policies = {
      DisableTelemetry = true;
      DisableDataCollectionSettings = true;

      # No donation, survey or news pop-ups: Thunderbird stops fetching them
      # at startup and every 6 hours.
      InAppNotification.Disabled = true;

      # Thunderbird starts at login; by default it then loads the online start
      # page (live.thunderbird.net) in the message pane. Policies, because
      # `settings` below only reach profiles declared here, and there are none.
      # "default" only changes the default: Settings > General can turn it on.
      Preferences."mailnews.start_page.enabled" = {
        Value = false;
        Status = "default";
      };

      ExtensionSettings = {
        "farahats9@yahoo.com" = {
          install_url = "https://addons.thunderbird.net/thunderbird/downloads/latest/simple-startup-minimizer/latest.xpi";
          installation_mode = "force_installed";
        };
      };
    };

    settings = {
      # Privacy and telemetry
      "toolkit.telemetry.enabled" = false;
      "datareporting.healthreport.uploadEnabled" = false;
      "datareporting.policy.dataSubmissionEnabled" = false;
    };
  };
}
