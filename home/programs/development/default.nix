{ pkgs, inputs, ... }:

{
  home.packages = with pkgs; [
    zed-editor
    nodejs_latest

    (python3.withPackages (python-pkgs: with python-pkgs; [
        numpy
    ]))
  ];
}
