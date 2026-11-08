{ pkgs, ... }:

let
  gameboost = pkgs.stdenv.mkDerivation {
    name = "gameboost";

    src = ./.;

    dontConfigure = true;

    # Dynamically linked on purpose: libc pages are shared with every other
    # process, so the daemon's real footprint (PSS) is ~220 KB versus ~810 KB
    # for a static build, whose private copy of libc code counts in full.
    buildPhase = ''
      runHook preBuild

      $CC -O2 -s -Wall gameboostd.c -o gameboostd

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -d "$out/libexec/gameboost"

      install -m755 gameboostd main.sh start.sh exit.sh notify.sh \
        "$out/libexec/gameboost/"

      runHook postInstall
    '';
  };
in
{
  systemd.services.gameboost = {
    description = "GameBoost game performance monitor";

    wantedBy = [ "graphical.target" ];

    after = [
      "graphical.target"
    ];

    # Used only by the one-shot hook scripts; the daemon itself needs nothing.
    path = with pkgs; [
      bash
      coreutils   # id
      procps      # pgrep, pkill
      psmisc      # killall
      systemd     # loginctl
      util-linux  # renice, ionice, setpriv
      libnotify   # notify-send
    ];

    serviceConfig = {
      Type = "simple";

      ExecStart =
        "${pkgs.bash}/bin/bash ${gameboost}/libexec/gameboost/main.sh";

      # The daemon runs exit.sh itself on SIGTERM. This covers a crash or
      # SIGKILL while game mode was active.
      ExecStopPost =
        "-${pkgs.bash}/bin/bash -c '[ -f /run/gameboost/running.flag ] && exec ${gameboost}/libexec/gameboost/exit.sh || true'";

      Restart = "on-failure";
      RestartSec = "2s";

      # Root-owned /run/gameboost holds the "game mode active" flag.
      # Primarily used to block auto-upgrades, and determine if game is running.
      RuntimeDirectory = "gameboost";

      # Lowest CPU priority. Hook scripts are reset to normal priority by the
      # daemon so they are not starved while a game saturates the CPU.
      Nice = 19;
      CPUWeight = 1;
      CPUSchedulingPolicy = "idle";

      # Lowest I/O priority
      IOWeight = 1;
      IOSchedulingClass = "idle";
      IOSchedulingPriority = 7;

      # Cheap, and makes `systemctl status` show CPU and memory use.
      CPUAccounting = true;
      MemoryAccounting = true;
    };
  };
}
