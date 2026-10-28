{ ... }:

{
  programs.plasma.input.mice = [
    {
      # Wireless
      name = "Logitech PRO X 2";
      vendorId = "046d";
      productId = "40a9";
      accelerationProfile = "none";
      enable = true;
    }

    {
      # Wireless receiver
      name = "Logitech USB Receiver";
      vendorId = "046d";
      productId = "c54d";
      accelerationProfile = "none";
      enable = true;
    }

    {
      # Wired
      name = "Logitech PRO X 2";
      vendorId = "046d";
      productId = "c09b";
      accelerationProfile = "none";
      enable = true;
    }
  ];
}
