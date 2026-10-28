{ ... }:


{
  programs.thunderbird = {
    enable = true;

    policies = {
      DisableTelemetry = true;
      DisableDataCollectionSettings = true;

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
