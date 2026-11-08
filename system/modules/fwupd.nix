{ config, lib, ... }:

let
  fwupd = config.services.fwupd;
in
{
  # fwupd's refresh timer fires hourly, and each run starts the fwupd daemon
  # (loads its plugins, probes every device) although the metadata is only
  # downloaded once it is a day old. Run it daily instead; --force skips only
  # that age check, so the metadata is still downloaded once a day.
  systemd = lib.mkIf fwupd.enable {
    timers.fwupd-refresh.timerConfig.OnCalendar = [ "" "daily" ];

    services.fwupd-refresh.serviceConfig.ExecStart = [
      ""
      "${fwupd.package}/bin/fwupdmgr refresh --force"
    ];
  };
}
