{ ... }:

{
  environment.sessionVariables = {
    # Enable native Wayland support in Proton where supported.
    PROTON_ENABLE_WAYLAND = "1";

    # Enable Proton's WoW64 mode (64-bit and 32-bit Windows applications).
    PROTON_USE_WOW64 = "1";

    # Limit the number of frames queued ahead in VKD3D-Proton (DirectX 12).
    # Lower values reduce latency but may decrease performance.
    VKD3D_SWAPCHAIN_LATENCY_FRAMES = "2";

    # Force immediate Vulkan presentation through Mesa.
    # Reduces VSync-related presentation latency but allows screen tearing.
    MESA_VK_WSI_PRESENT_MODE = "immediate";

    # Limit maximum frame latency in DXVK (DirectX 9, 10 and 11).
    DXVK_CONFIG = "dxgi.maxFrameLatency=2;d3d9.maxFrameLatency=2";
  };
}
