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
    runtimeInputs = [ pkgs.nix pkgs.git ];
    text = builtins.replaceStrings
      [ "@flakeDir@" ]
      [ flakeDir ]
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
      # Gates and `nix flake update` both live in main.sh. Exit 1 = quiet skip.
      ExecCondition = lib.getExe upgradeGate;
      # Keeps PWD == flakeDir when the service re-evaluates the config,
      # so the detected path survives automatic upgrades.
      WorkingDirectory = flakeDir;
    };

    # No preStart: main.sh updates the flake, and only when an upgrade is due.

    postStart = ''
      printf '%(%s)T\n' -1 > ${stamp}.tmp
      mv ${stamp}.tmp ${stamp}
    '';
  };
}
