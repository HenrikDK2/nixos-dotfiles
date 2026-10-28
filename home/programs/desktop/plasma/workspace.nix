{ ... }:

{
  programs.plasma.workspace = {
    lookAndFeel = "org.kde.breezedark.desktop";
    colorScheme = "BreezeDark";

    wallpaperSlideShow = {
      path = "${./files/Wallpapers}";
      interval = 1200;
    };
  };
}
