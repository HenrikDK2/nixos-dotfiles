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

### Below is a clean way to redirect to another .exe in steam launch options
# cmd=(%command%); cmd[-1]="/path/to/your/custom.exe"; "${cmd[@]}"

# Possible to add envs like this:
# cmd=(%command%); cmd[-1]="/path/to/your/custom.exe"; env PROTON_LOG=1 "${cmd[@]}"
