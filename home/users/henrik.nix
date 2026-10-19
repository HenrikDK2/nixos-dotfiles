{ pkgs, lib, helpers, inputs, ... }:

let
  username = "henrik";

  gitUsername = "HenrikDK2";
  gitEmail = "30632653+HenrikDK2@users.noreply.github.com";
in
{
  users.users.${username} = {

    isNormalUser = true;

    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    initialPassword = "1234";
  };

  home-manager.extraSpecialArgs = {
    inherit gitUsername gitEmail;
  };

  home-manager.users.${username} = {
    home.stateVersion = "26.05";

    home.pointerCursor = {
      enable = true;

      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;

      x11 = {
        enable = true;
        defaultCursor = "left_ptr";
        size = 24;
      };

      gtk.enable = true;
    };

    imports = lib.flatten [
      (helpers.importAll ../services)
      (helpers.importAll ../programs)
    ];

    home.packages = with pkgs; [
      wl-clipboard
      p7zip
      mpv

      zed-editor
      discord
      tidal-hifi

      gamescope
      steam
      faugus-launcher
      proton-cachyos_x86_64_v3
      protontricks
      protonplus
    ];

    # Add udev rules for steam devices
    hardware.steam-hardware.enable = true;

    # Expose CachyOS Proton to Steam.
    xdg.dataFile."Steam/compatibilitytools.d/proton-cachyos".source =
      "${pkgs.proton-cachyos_x86_64_v3}";

    xdg.autostart = {
      enable = true;

      entries = with pkgs; [
        "${steam}/share/applications/steam.desktop"
        "${discord}/share/applications/discord.desktop"
        "${thunderbird}/share/applications/thunderbird.desktop"
      ];
    };
  };
}

### Below is a clean way to redirect to another .exe in steam launch options
# cmd=(%command%); cmd[-1]="/path/to/your/custom.exe"; "${cmd[@]}"

# Possible to add envs like this:
# cmd=(%command%); cmd[-1]="/path/to/your/custom.exe"; env PROTON_LOG=1 "${cmd[@]}"
