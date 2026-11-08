{ pkgs, ... }:

{
  networking.hostName = "nixos";

  # ModemManager only serves mobile-broadband modems, and it probes serial and
  # USB devices as they appear. NetworkManager turns it on by default.
  networking.modemmanager.enable = false;

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
