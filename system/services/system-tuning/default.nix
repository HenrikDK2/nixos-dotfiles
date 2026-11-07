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

    # Only sysctl is needed; coreutils/systemd are in every unit's default PATH.
    path = [ pkgs.procps ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash ${./script.sh}";
    };
  };
}
