{ pkgs, inputs, ... }:

{
  home.packages = with pkgs; [
    # Remove once zed-editor is unpinned
    inputs.nixpkgs-zed.legacyPackages.${pkgs.stdenv.hostPlatform.system}.zed-editor
    nodejs_latest
  ];
}
