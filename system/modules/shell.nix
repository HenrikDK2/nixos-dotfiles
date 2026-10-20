{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.fish;
  programs.fish = {
    enable = true;

    shellAliases = {
      switch = "sudo nixos-rebuild switch --impure --flake $HOME/nixos";
    };

    interactiveShellInit = ''
      set fish_greeting
      stty lnext ""
    '';
  };
}
