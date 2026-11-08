{ pkgs, ... }:

{
  users.defaultUserShell = pkgs.fish;
  programs.fish = {
    enable = true;

    # Translate the NixOS shell-init files to fish at build time, instead of
    # starting bash (foreign-env) twice in every new shell.
    useBabelfish = true;

    shellAliases = {
      nix-switch = "sudo nixos-rebuild switch --impure --flake ./";
    };

    interactiveShellInit = ''
      set fish_greeting
      stty lnext ""
    '';
  };
}
