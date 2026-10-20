{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.fish;
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      set fish_greeting
      stty lnext ""
    '';
  };
}
