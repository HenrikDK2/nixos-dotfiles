{ inputs, lib, pkgs, ... }:

let
  low-latency-layer = pkgs.stdenv.mkDerivation {
    pname = "low-latency-layer";
    version = "0.2.0";

    src = inputs.low-latency-layer;

    nativeBuildInputs = with pkgs; [
      cmake
      ninja
    ];

    buildInputs = with pkgs; [
      vulkan-headers
      vulkan-loader
      vulkan-utility-libraries
    ];

    env.NIX_CXXFLAGS_COMPILE = "-O2 -march=x86-64-v3";

    cmakeFlags = [
      "-DCMAKE_BUILD_TYPE=Release"
      "-DCMAKE_CXX_FLAGS_RELEASE=-O2"
      "-DVulkan_LIBRARY=${pkgs.vulkan-loader}/lib/libvulkan.so"
    ];

    meta = {
      description = "Hardware-agnostic Vulkan input latency reduction layer";
      homepage = "https://github.com/Korthos-Software/low_latency_layer";
      license = lib.licenses.mit;
      platforms = [ "x86_64-linux" ];
    };
  };
in
{
  environment.systemPackages = [ low-latency-layer ];

  # Enable the implicit Vulkan layer globally for applications in the session.
  environment.sessionVariables.LOW_LATENCY_LAYER = "1";
}
