{ pkgs, config, lib, ... }:

let
  # "nvidia" or "amd"
  variant = "amd";
in
{
  config = lib.mkMerge [

    # Shared graphics configuration
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };
    }

    # NVIDIA variant
    (lib.mkIf (variant == "nvidia") {
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.graphics.extraPackages = with pkgs; [ nvidia-vaapi-driver ];

      boot.kernelModules = [
        "nvidia"
        "nvidia_modeset"
        "nvidia_uvm"
        "nvidia_drm"
        "i2c-nvidia_gpu"
      ];

      hardware.nvidia-container-toolkit.enable = true;

      # Podman CDI configuration
      virtualisation.containers.containersConf.settings.engine.cdi_spec_dirs = [
        "/etc/cdi"
        "/var/run/cdi"
      ];

      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = false;
        powerManagement.finegrained = false;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };
    })

    # AMD variant
    (lib.mkIf (variant == "amd") {
      hardware.amdgpu.overdrive.enable = true;
      hardware.graphics.package = pkgs.mesa-x86_64-v3;

      environment.systemPackages = [
        pkgs.low-latency-layer-lto-x86_64-v3
      ];

      environment.sessionVariables.LOW_LATENCY_LAYER = "1";
    })
  ];
}
