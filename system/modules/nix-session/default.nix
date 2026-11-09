{ config, pkgs, ... }:

# nix-session: build a flake package once and use its programs from every
# terminal until reboot, without touching the dotfiles. See script.sh.

let
  nix-session = pkgs.writeShellApplication {
    name = "nix-session";

    runtimeInputs = [
      config.nix.package
      pkgs.coreutils
    ];

    text = builtins.readFile ./script.sh;
  };
in
{
  environment.systemPackages = [ nix-session ];

  # Put the session's bin folder first in PATH, so a build added with
  # nix-session wins over an installed version. It is added even before the
  # folder exists, so programs added later show up in already-open terminals.
  programs.fish.shellInit = ''
    if set -q XDG_RUNTIME_DIR; and not contains -- $XDG_RUNTIME_DIR/nix-session/bin $PATH
        set -gx PATH $XDG_RUNTIME_DIR/nix-session/bin $PATH
    end
  '';

  programs.bash.interactiveShellInit = ''
    if [ -n "''${XDG_RUNTIME_DIR-}" ]; then
      case ":$PATH:" in
        *":$XDG_RUNTIME_DIR/nix-session/bin:"*) ;;
        *) PATH="$XDG_RUNTIME_DIR/nix-session/bin:$PATH" ;;
      esac
    fi
  '';
}
