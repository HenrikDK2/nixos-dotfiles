{ config, lib, pkgs, ... }:

# Background maintenance waits while a game is active (GameBoost's
# running.flag) and catches up afterwards.
#
# A run that systemd skips still counts as run for the timer (Persistent=
# only catches up runs missed while the machine was off), so skipping a
# weekly timer would push the job back a whole week. Instead each timer
# fires daily and starts NAME-scheduled.service, which starts the job once
# its last successful run is old enough: a job that lands during play
# retries the next day. Manual starts (`systemctl start nix-gc`) go straight
# to the job and only wait for a running game.

let
  stampDir = "/var/lib/gameboost-maint";
  systemctl = "${config.systemd.package}/bin/systemctl";

  gate = pkgs.writeShellApplication {
    name = "gameboost-maint-gate";
    text = ''
      # gameboost-maint-gate game                 (the job's ExecCondition)
      # gameboost-maint-gate due NAME MIN_AGE_S   (NAME-scheduled's ExecCondition)
      # gameboost-maint-gate done NAME            (the job's ExecStartPost)
      if [[ $1 != done && -e /run/gameboost/running.flag ]]; then
        echo "A game is running (GameBoost); skipping until the next check."
        exit 1
      fi

      case $1 in
        due)
          # A missing, unreadable or future stamp means "due".
          if read -r last 2>/dev/null < "${stampDir}/$2" && [[ $last =~ ^[0-9]+$ ]] &&
            ((EPOCHSECONDS - last >= 0 && EPOCHSECONDS - last < $3)); then
            echo "Last run $(((EPOCHSECONDS - last) / 3600))h ago; not due yet."
            exit 1
          fi
          ;;
        done)
          stamp="${stampDir}/$2"
          printf '%s\n' "$EPOCHSECONDS" > "$stamp.tmp" && mv -f "$stamp.tmp" "$stamp"
          ;;
      esac
    '';
  };

  # The intervals are a little under the nominal ones, so the timers'
  # random delays never push a run back by a whole extra day.
  week = 6 * 86400 + 12 * 3600;
  day = 23 * 3600;

  # "+": run as root even for units with User= or a read-only filesystem.
  gameCheck = "+${lib.getExe gate} game";
  stampDone = name: "+${lib.getExe gate} done ${name}";

  # The job waits for a running game and stamps each successful run (in a
  # oneshot, ExecStartPost runs only after ExecStart succeeded). NAME.timer
  # starts NAME-scheduled.service instead, which starts the job when due.
  gated = name: minAge: {
    services.${name}.serviceConfig = {
      ExecCondition = gameCheck;
      ExecStartPost = [ (stampDone name) ];
    };
    services."${name}-scheduled" = {
      description = "Start ${name}.service if it is due";
      serviceConfig = {
        Type = "oneshot";
        ExecCondition = "+${lib.getExe gate} due ${name} ${toString minAge}";
        ExecStart = "${systemctl} start --no-block ${name}.service";
      };
    };
    timers.${name}.timerConfig.Unit = "${name}-scheduled.service";
  };
in
{
  # Daily checks; see nix.gc.dates in configuration.nix and fwupd.nix for
  # the other timers.
  services.fstrim.interval = "daily";

  systemd = lib.mkMerge [
    {
      tmpfiles.rules = [ "d ${stampDir} 0755 root root -" ];

      # Store deduplication right after each GC that actually ran (never
      # after a skipped one), so it never hashes paths the GC is about to
      # delete. It has no timer of its own (configuration.nix).
      services.nix-gc.serviceConfig.ExecStartPost =
        [ "${systemctl} start --no-block nix-optimise.service" ];
      services.nix-optimise.serviceConfig.ExecCondition = gameCheck;
    }
    (gated "nix-gc" week)
    (lib.mkIf config.services.fstrim.enable (gated "fstrim" week))
    (lib.mkIf config.services.fwupd.enable (gated "fwupd-refresh" day))
  ];
}
