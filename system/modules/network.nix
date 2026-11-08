{ pkgs, lib, helpers, ... }:

{
  networking.hostName = "nixos";

  # ModemManager only serves mobile-broadband modems, and it probes serial and
  # USB devices as they appear. NetworkManager turns it on by default.
  networking.modemmanager.enable = false;

  # Desktops: no boot-time start. NetworkManager starts wpa_supplicant over
  # D-Bus (the package's activation file points at this same unit) as soon as
  # a Wi-Fi card or USB dongle needs it, so without Wi-Fi it never runs.
  # Laptops keep the stock boot-time start.
  systemd.services.wpa_supplicant.wantedBy =
    lib.mkIf (!helpers.isLaptop) (lib.mkForce [ ]);

  networking.networkmanager = {
    enable = true;
    dns = "default";

    # Prefer Cloudflare DNS over DHCP-provided DNS
    insertNameservers = [
      "1.1.1.1"
      "1.0.0.1"
    ];

    plugins = with pkgs; [
      networkmanager-openvpn
    ];
  };
}
