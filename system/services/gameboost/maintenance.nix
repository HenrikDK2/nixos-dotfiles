{ config, lib, pkgs, ... }:

# Background maintenance skips a run while a game is active (GameBoost's
# running.flag), the same way auto-upgrade already does, and catches up
# afterwards.
#
# A run that systemd skips still counts as run for the timer (Persistent=
# only catches up runs missed while the machine was off), so skipping a
# weekly timer would push the job back a whole week. Instead each timer
# checks daily, and the gate lets the job through once its last successful
# run is old enough: a job that lands during play retries the next day.

let
  stampDir = "/var/lib/gameboost-maint";

  gate = pkgs.writeShellApplication {
    name = "gameboost-maint-gate";
    text = ''
      # gameboost-maint-gate check NAME MIN_AGE_SECONDS  (ExecCondition)
      # gameboost-maint-gate done NAME                   (ExecStartPost)
      stamp="${stampDir}/$2"

      case $1 in
        check)
          if [[ -e /run/gameboost/running.flag ]]; then
            echo "A game is running (GameBoost); skipping until the next check."
            exit 1
          fi
          # A missing, unreadable or future stamp means "due".
          if read -r last 2>/dev/null < "$stamp" && [[ $last =~ ^[0-9]+$ ]] &&
            ((EPOCHSECONDS - last >= 0 && EPOCHSECONDS - last < $3)); then
            echo "Last run $(((EPOCHSECONDS - last) / 3600))h ago; not due yet."
            exit 1
          fi
          ;;
        done)
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
  gated = name: minAge: {
    ExecCondition = "+${lib.getExe gate} check ${name} ${toString minAge}";
    ExecStartPost = "+${lib.getExe gate} done ${name}";
  };
in
{
  systemd.tmpfiles.rules = [ "d ${stampDir} 0755 root root -" ];

  # Daily checks; see nix.gc.dates in configuration.nix (nix-optimise runs
  # after each successful GC) and fwupd.nix for the other timers.
  services.fstrim.interval = "daily";

  systemd.services = {
    nix-gc.serviceConfig = gated "nix-gc" week;
    # Oneshot, so the stamp is written when the run has finished successfully,
    # not when it starts (the upstream unit has no Type, i.e. simple).
    nix-optimise.serviceConfig = gated "nix-optimise" week // { Type = "oneshot"; };
    fstrim.serviceConfig = lib.mkIf config.services.fstrim.enable (gated "fstrim" week);
    fwupd-refresh.serviceConfig = lib.mkIf config.services.fwupd.enable (gated "fwupd-refresh" day);
  };
}
