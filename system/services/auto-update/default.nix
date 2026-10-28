{ config, lib, pkgs, inputs, ... }:

let
  pwd = builtins.getEnv "PWD";
  flakeDir =
    if pwd != "" && builtins.pathExists (pwd + "/flake.nix")
    then pwd
    else "/etc/nixos";

  stamp = "/var/lib/generation-stamp";

  upgradeGate = pkgs.writeShellApplication {
    name = "nixos-upgrade-gate";
    bashOptions = [ ];
    runtimeInputs = with pkgs; [ nix git gawk gnugrep coreutils ];
    text = builtins.replaceStrings
      [ "@flakeDir@" "@hostName@" ]
      [ flakeDir config.networking.hostName ]
      (builtins.readFile ./main.sh);
  };
in
{
  system.autoUpgrade = {
    enable = true;
    operation = "boot";
    flake = flakeDir;
    allowReboot = false;

    dates = "hourly";
    randomizedDelaySec = "0";
    persistent = true;

    flags = [ "--impure" "-L" ];
  };

  systemd.services.nixos-upgrade = {
    path = [ pkgs.nix pkgs.git ];

    serviceConfig = {
      ExecCondition = lib.getExe upgradeGate;
      WorkingDirectory = flakeDir;
    };

    postStart = ''
      printf '%(%s)T\n' -1 > ${stamp}.tmp
      mv ${stamp}.tmp ${stamp}
    '';
  };
}
