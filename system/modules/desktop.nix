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

  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    kate
    qrca
    krunner
  ];
}
