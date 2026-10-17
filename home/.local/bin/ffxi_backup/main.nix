{ pkgs, ... }:

let
  ffxi-backup = pkgs.writeShellApplication {
    name = "ffxi-backup";

    runtimeInputs = with pkgs; [
      p7zip
      coreutils
    ];

    text = builtins.readFile ./script.sh;
  };
in
{
  home.packages = [
    ffxi-backup
  ];
}
