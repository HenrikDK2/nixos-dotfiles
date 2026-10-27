{ config, lib, pkgs, inputs, ... }:

let
  # Directory the rebuild was invoked from, if it actually holds a flake.
  # Falls back to /etc/nixos (pure eval, or run from elsewhere).
  pwd = builtins.getEnv "PWD";
  flakeDir =
    if pwd != "" && builtins.pathExists (pwd + "/flake.nix")
    then pwd
    else "/etc/nixos";

  stamp = "/var/lib/generation-stamp";

  upgradeGate = pkgs.writeShellApplication {
    name = "nixos-upgrade-gate";
    bashOptions = [ ];
    text = builtins.readFile ./main.sh;
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
      # Keeps PWD == flakeDir when the service re-evaluates the config,
      # so the detected path survives automatic upgrades.
      WorkingDirectory = flakeDir;
    };

    preStart = ''
      nix flake update --flake ${flakeDir}
    '';

    postStart = ''
      printf '%(%s)T\n' -1 > ${stamp}.tmp
      mv ${stamp}.tmp ${stamp}
    '';
  };
}
