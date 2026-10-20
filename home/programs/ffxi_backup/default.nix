{ pkgs, ... }:

let
  ffxi-backup = pkgs.writeShellApplication {
    name = "ffxi-backup";

    runtimeInputs = with pkgs; [
      p7zip
      coreutils
      gnugrep
      findutils
      gawk
    ];

    text = builtins.readFile ./script.sh;
  };
in
{
  home.packages = [
    ffxi-backup
  ];
}
