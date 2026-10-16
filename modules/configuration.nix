
{ inputs, helpers, lib, pkgs, ... }:

{
  imports = lib.flatten [
    /etc/nixos/hardware-configuration.nix
    (helpers.importAll ./home/users)
  ];

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Copenhagen";
  console.keyMap = "dk-latin1";

  # Locale
  i18n = {
    defaultLocale = "en_DK.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "da_DK.UTF-8";
      LC_IDENTIFICATION = "da_DK.UTF-8";
      LC_MEASUREMENT = "da_DK.UTF-8";
      LC_MONETARY = "da_DK.UTF-8";
      LC_NAME = "da_DK.UTF-8";
      LC_NUMERIC = "da_DK.UTF-8";
      LC_PAPER = "da_DK.UTF-8";
      LC_TELEPHONE = "da_DK.UTF-8";
      LC_TIME = "da_DK.UTF-8";
    };
  };

  # Boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # GPU hardware acceleration
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.amdgpu.overdrive.enable = true;

  # Desktop environment
  services = {
    xserver = {
      enable = true;
      xkb.layout = "dk";
    };

    printing.enable = true;
    lact.enable = true;
    openssh.enable = true;

    desktopManager.plasma6.enable = true;

    displayManager.sddm.enable = true;
    displayManager.autoLogin = {
      enable = true;
      user = "henrik";
    };

    pulseaudio.enable = false;
    pipewire = {
      enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
      pulse.enable = true;
    };
  };

  # Exclude unwanted KDE applications
  programs.kde-pim.enable = false;
  environment.plasma6.excludePackages = with pkgs.kdePackages; [
    kate
    qrca
  ];

  # Security
  security.rtkit.enable = true;

  # Nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Automatic updates
  system.autoUpgrade = {
    enable = true;
    flake = inputs.self.outPath;
    dates = "daily";
    flags = [
      "--update-input"
      "nixpkgs"
      "--no-write-lock-file"
      "-L"
    ];
  };

  system.stateVersion = "26.05";
}
