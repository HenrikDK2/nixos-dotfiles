{ inputs, ... }:

{
  programs.lookapp = {
    enable = true;
    theme = "custom";

    settings = {
      # Breeze Dark panel surface: #202326
      ui_tint_red = 0.125;
      ui_tint_green = 0.137;
      ui_tint_blue = 0.149;

      # Breeze text: #fcfcfc
      ui_font_red = 0.988;
      ui_font_green = 0.988;
      ui_font_blue = 0.988;
      ui_font_opacity = 1.0;
      ui_font_name = "Noto Sans";
      ui_font_size = 14;

      # Subtle Breeze Dark frame: #45494d
      ui_border_thickness = 1;
      ui_border_red = 0.271;
      ui_border_green = 0.286;
      ui_border_blue = 0.302;
      ui_border_opacity = 1.0;

      # Subtle corner rounding
      ui_surface_radius = 0.6;

      # KWin background blur
      ui_compositor_blur = true;
    };
  };
}
