{ pkgs, ... }:

{
  hardware.amdgpu.overdrive.enable = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  environment.systemPackages = [
    pkgs.low-latency-layer
  ];

  environment.sessionVariables = {
    LOW_LATENCY_LAYER = "1";
  };
}
