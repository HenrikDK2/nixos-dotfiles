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
    runtimeInputs = [ pkgs.nix pkgs.git pkgs.systemd ];
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
    # Flake system: inputs are updated by main.sh. --upgrade would only add a
    # nix-channel --update of a channel this system does not use.
    upgrade = false;

    # Not on a calendar: see the timer below (`dates` is unused).
    persistent = false;

    flags = [ "--impure" "-L" ];
  };

  # Checked once per boot, since any amount of time may have passed while the
  # PC was off, and after that only when an upgrade is due again: main.sh
  # lets one through 24 h after the last successful upgrade.
  # - 10 min after boot, after the login rush (Steam, Discord, Thunderbird).
  # - When that check finds the last upgrade too recent, main.sh schedules
  #   the next check for the moment it becomes due (nixos-upgrade-due.timer).
  # - 24 h after the previous run ended, for long uptimes.
  # - A failed upgrade (or a failed `nix flake update`, e.g. no network yet)
  #   is retried an hour later until it succeeds (Restart= below).
  # - A run skipped because a game was running is started again by GameBoost
  #   when the game exits (/run/nixos-upgrade.deferred, see exit.sh).
  systemd.services.nixos-upgrade.startAt = lib.mkForce [ ];
  systemd.timers.nixos-upgrade = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitInactiveSec = "24h";
    };
  };

  systemd.services.nixos-upgrade = {
    path = [ pkgs.nix pkgs.git ];

    serviceConfig = {
      # Builds run in-process as root, inside this unit's cgroup, so the idle
      # slice (see configuration.nix) covers every compiler/substituter it spawns.
      Slice = "background.slice";
      IOSchedulingClass = "idle";

      # Gates and `nix flake update` both live in main.sh. Exit 1 = quiet
      # skip, exit 255 = failed (retried below).
      ExecCondition = lib.getExe upgradeGate;
      Restart = "on-failure";
      RestartSec = "1h";
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
