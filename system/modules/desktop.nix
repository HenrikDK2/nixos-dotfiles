{ pkgs, ... }:

{
  services = {
    xserver = {
      enable = true;
      xkb.layout = "dk";
    };

    printing.enable = true;
    lact.enable = true;
    openssh.enable = true;

    desktopManager.plasma6.enable = true;
    displayManager.plasma-login-manager.enable = true;
  };

  programs.kde-pim.enable = false;
  environment.plasma6.excludePackages =
    with pkgs.kdePackages; [
      kate
      qrca
    ];
}
