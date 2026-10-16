{ pkgs, ... }:

{
  systemd.services.system-tuning = {
    description = "Apply system performance and security optimizations";
    wantedBy = [ "multi-user.target" ];
    wants = [ "NetworkManager.service" ];

    after = [
      "systemd-sysctl.service"
      "NetworkManager.service"
    ];

    path = with pkgs; [
      coreutils
      gawk
      gnugrep
      procps
      systemd
      networkmanager
    ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${./script.sh}";
    };
  };
}
