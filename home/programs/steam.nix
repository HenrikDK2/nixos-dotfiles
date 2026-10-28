{ pkgs, ... }:

{
  home.packages = [ pkgs.steam ];

  # Expose CachyOS Proton to Steam.
  xdg.dataFile."Steam/compatibilitytools.d/proton-cachyos-x86_64-v3".source =
    "${pkgs.proton-cachyos-x86_64-v3}/share/steam/compatibilitytools.d/proton-cachyos-x86_64-v3";

  programs.steam.config = {
    enable = true;
    defaultCompatTool = "proton-cachyos-x86_64-v3";
  };
}
