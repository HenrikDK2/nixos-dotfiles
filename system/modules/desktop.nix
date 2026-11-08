{ pkgs, ... }:

{
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
