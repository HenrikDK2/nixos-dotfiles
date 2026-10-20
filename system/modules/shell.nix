{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.fish;
  programs.fish = {
    enable = true;

    shellAliases = {
      nix-switch = "sudo nixos-rebuild switch --impure --flake $HOME/nixos";
    };

    interactiveShellInit = ''
      set fish_greeting
      stty lnext ""
    '';
  };
}
