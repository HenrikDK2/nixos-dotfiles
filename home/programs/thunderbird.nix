{ ... }:

{
  programs.thunderbird = {
    enable = true;

    policies = {
      DisableTelemetry = true;
      DisableDataCollectionSettings = true;
    };

    settings = {
      # Privacy and telemetry
      "toolkit.telemetry.enabled" = false;
      "datareporting.healthreport.uploadEnabled" = false;
      "datareporting.policy.dataSubmissionEnabled" = false;
    };
  };
}
