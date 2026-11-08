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

    # nixos-rebuild switch restarts systemd-sysctl whenever the NixOS sysctl
    # set changes, which puts the NixOS defaults back over these values.
    # PartOf + RemainAfterExit restart this unit with it (and on its own
    # changes), so the tuned values are reapplied instead of lost until reboot.
    partOf = [ "systemd-sysctl.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.bash}/bin/bash ${./script.sh}";
    };
  };
}
