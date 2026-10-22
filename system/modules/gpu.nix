{ pkgs, ... }:

{
  hardware.amdgpu.overdrive.enable = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # Use the custom Mesa build for graphics
  hardware.graphics.package = pkgs.mesa-x86_64-v3;

  # https://github.com/Korthos-Software/low_latency_layer
  environment.systemPackages = [
    pkgs.low-latency-layer-lto-x86_64-v3
  ];

  environment.sessionVariables.LOW_LATENCY_LAYER = "1";
}
