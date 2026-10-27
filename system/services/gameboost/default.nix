{ pkgs, ... }:

let
  gameboost = pkgs.stdenv.mkDerivation {
    pname = "gameboost";
    version = "1.0";

    src = ./.;

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      $CC -O3 -pthread optimized_ps.c -o optimized_ps

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      install -d "$out/libexec/gameboost"

      install -m755 main.sh \
        "$out/libexec/gameboost/main.sh"

      install -m755 start.sh \
        "$out/libexec/gameboost/start.sh"

      install -m755 exit.sh \
        "$out/libexec/gameboost/exit.sh"

      install -m755 optimized_ps \
        "$out/libexec/gameboost/optimized_ps"

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

    path = with pkgs; [
      bash
      coreutils
      gawk
      gnugrep
      procps
      systemd
      util-linux
      psmisc
      pciutils
      libnotify
    ];

    serviceConfig = {
      Type = "simple";

      ExecStart =
        "${pkgs.bash}/bin/bash ${gameboost}/libexec/gameboost/main.sh";

      Restart = "on-failure";
      RestartSec = "2s";

      # Lowest CPU priority
      Nice = 19;
      CPUWeight = 1;
      CPUSchedulingPolicy = "idle";

      # Lowest I/O priority
      IOWeight = 1;
      IOSchedulingClass = "idle";
      IOSchedulingPriority = 7;
    };
  };
}
