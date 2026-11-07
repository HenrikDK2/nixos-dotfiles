{ pkgs, lib, ... }:

let
  tidalConfigScript = pkgs.writeShellScript "tidal-config" ''
    CONFIG="$HOME/.config/tidal-hifi/config.json"

    mkdir -p "$(dirname "$CONFIG")"
    [ -f "$CONFIG" ] || echo '{}' > "$CONFIG"

    # Only replace the config if jq succeeded: on malformed JSON jq writes
    # nothing, and moving its output over the config would empty it.
    if ${pkgs.jq}/bin/jq \
      '.menuBar = false | .notifications = false' \
      "$CONFIG" > "$CONFIG.tmp"; then
      mv "$CONFIG.tmp" "$CONFIG"
    else
      rm -f "$CONFIG.tmp"
      echo "tidal-hifi: $CONFIG is not valid JSON; left unchanged." >&2
    fi
  '';
in
{
  home.packages = [
    pkgs.tidal-hifi
    pkgs.jq
  ];

  xdg.configFile."applications/tidal-hifi.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=TIDAL Hi-Fi
    Exec=${pkgs.tidal-hifi}/bin/tidal-hifi --no-sandbox %U
    Terminal=false
    Categories=AudioVideo;Audio;Player;
  '';

  home.activation.tidalConfig =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${tidalConfigScript}
    '';
}
