{ ... }:

{
  programs.mpv = {
    enable = true;

    # mpv decodes in software by default; use the GPU's video decoder when it
    # is known to work, falling back to software otherwise.
    config.hwdec = "auto-safe";
  };
}
