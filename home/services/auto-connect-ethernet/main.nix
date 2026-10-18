{ config, lib, pkgs, ... }:

{
  systemd.user.services.connect-ethernet = {
    Unit = {
      Description = "Connect automatically to Ethernet";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      Environment = [
        "PATH=${lib.makeBinPath (with pkgs; [ coreutils gawk networkmanager ])}"
      ];
      ExecStart = "${pkgs.bash}/bin/bash ${./script.sh}";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
