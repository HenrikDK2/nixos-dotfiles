{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.fish;
  programs.fish = {
    enable = true;

    shellAliases = {
      nix-switch = "sudo nixos-rebuild switch --impure --flake ./";
    };

    interactiveShellInit = ''
      set fish_greeting
      stty lnext ""
    '';
  };
}
