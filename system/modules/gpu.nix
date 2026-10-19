{ pkgs, ... }:

{
  hardware.amdgpu.overdrive.enable = true;
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;

  # Use the custom Mesa build for graphics
  hardware.graphics.package = pkgs.mesa-x86_64-v3;
}
