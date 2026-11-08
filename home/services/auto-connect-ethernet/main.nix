{ config, lib, pkgs, helpers, ... }:

{
  # Desktops only: a laptop may have no Ethernet port (the script then fails at
  # every login), and NetworkManager's own autoconnect covers it there.
  systemd.user.services.connect-ethernet = lib.mkIf (!helpers.isLaptop) {
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
