
{ pkgs, ... }:

let
  tidalConfigScript = pkgs.writeShellScript "tidal-config" ''
    CONFIG="$HOME/.config/tidal-hifi/config.json"

    mkdir -p "$(dirname "$CONFIG")"
    [ -f "$CONFIG" ] || echo '{}' > "$CONFIG"

    ${pkgs.jq}/bin/jq \
      '.menuBar = false | .notifications = false' \
      "$CONFIG" > "$CONFIG.tmp"

    mv "$CONFIG.tmp" "$CONFIG"
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

  home.activation.tidalConfig = ''
    ${tidalConfigScript}
  '';
}
