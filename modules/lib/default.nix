{ lib }:

{
  importAll = dir:
    let
      files = builtins.readDir dir;
    in
    map
      (name: dir + "/${name}")
      (lib.filter
        (name:
          files.${name} == "regular"
          && builtins.match ".*\\.nix" name != null
        )
        (builtins.attrNames files));
}
