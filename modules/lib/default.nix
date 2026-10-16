
{ lib }:

let
  importAll = dir:
    let
      files = builtins.readDir dir;
    in
    lib.concatMap
      (name:
        let
          path = dir + "/${name}";
          type = files.${name};
        in
        if type == "directory" then
          importAll path
        else if
          type == "regular"
          && builtins.match ".*\\.nix" name != null
        then
          [ path ]
        else
          [ ]
      )
      (builtins.attrNames files);
in
{
  inherit importAll;
}
