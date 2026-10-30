{ pkgs, ... }:

{
  networking.hostName = "nixos";

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
