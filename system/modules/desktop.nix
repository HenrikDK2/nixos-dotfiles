{ lib, pkgs, ... }:

let
  # nixpkgs deletes KDE's service cache (ksycoca) at every login (twice) and
  # every switch, because KDE can't see changes inside /nix/store; the first
  # KDE process then rebuilds it from scratch on the login path. Only delete
  # it when the system (which includes Home Manager) actually changed. Apps
  # in ~/.local/share/applications are still picked up by KDE itself.
  rebuildSycocaIfChanged = ''
    cache="''${XDG_CACHE_HOME:-$HOME/.cache}"
    current="$(readlink -f /run/current-system)"
    if [ "$(cat "$cache/nixos-ksycoca-system" 2>/dev/null)" != "$current" ]; then
      rm -fv "$cache/ksycoca"*
      mkdir -p "$cache"
      printf '%s\n' "$current" > "$cache/nixos-ksycoca-system"
    fi
  '';
in
{
  system.userActivationScripts.rebuildSycoca = lib.mkForce rebuildSycocaIfChanged;
  systemd.user.services.nixos-rebuild-sycoca.script = lib.mkForce rebuildSycocaIfChanged;

  # Session services with nothing to do here, masked:
  # - KDE's UnifiedPush distributor: push for NeoChat/Tokodon/Itinerary,
  #   none of which are installed; it only idles all session.
  # - The GTK global-menu proxy: there is no global menu in the panel or
  #   title bar to feed.
  # - kaccess: only forwards X11 bell events to KWin, so old X11/XWayland
  #   apps ringing the terminal bell are now silent.
  systemd.user.services = {
    kunifiedpush-distributor.enable = false;
    plasma-gmenudbusmenuproxy.enable = false;
    plasma-kaccess.enable = false;
  };

  services = {
    xserver = {
      enable = true;
      xkb.layout = "dk";
    };

    printing.enable = true;
    lact.enable = true;
    geoclue2.enable = false;

    # Screen reader and text-to-speech, on by default with Plasma. Not used
    # here; off, websites can't start speech-dispatcher through Firefox either.
    orca.enable = false;
    speechd.enable = false;

    desktopManager.plasma6.enable = true;
    displayManager.plasma-login-manager.enable = true;
  };

  programs.appimage = {
    enable = true;
    binfmt = true;

    package = pkgs.appimage-run.override {
      extraPkgs = pkgs: [
        pkgs.libgpg-error
        pkgs.nghttp2
      ];
    };
  };

  programs.kde-pim.enable = false;

  # Offline NixOS manual (nixos-help, man configuration.nix) and info pages.
  # Building the manual's option docs makes every evaluation slower; ordinary
  # man pages and /share/doc stay.
  documentation.nixos.enable = false;
  documentation.info.enable = false;

  # fish turns on the man-page index (for `man <Tab>` completions) and has it
  # rebuilt at every boot: an rsync --checksum of every man page plus mandb.
  # Build it with the system instead (during auto-upgrade, in the background
  # slice); man, apropos and fish completions work the same.
  documentation.man.cache.generateAtRuntime = false;

  # Started over D-Bus on first use (System Settings > Users, the account
  # portal) instead of at every boot; no session component needs it at login.
  systemd.services.accounts-daemon.wantedBy = lib.mkForce [ ];

  environment = {
    sessionVariables.SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    plasma6.excludePackages = with pkgs.kdePackages; [
      kate
      qrca
      krunner
      # Installed only because fwupd is on; firmware updates still work with
      # `fwupdmgr`.
      discover
      # Unused here: remote desktop server, music player, offline help and the
      # on-screen keyboard (no touchscreen).
      krdp
      elisa
      khelpcenter
      plasma-keyboard
      qtvirtualkeyboard
    ];
  };
}
