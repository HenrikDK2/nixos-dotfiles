
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

  # Same test as is_laptop in the GameBoost and system-tuning scripts: a
  # battery under <root>/sys/class/power_supply means a laptop.
  hasBattery = root:
    builtins.any
      (bat: builtins.pathExists "${root}/sys/class/power_supply/${bat}")
      [ "BAT0" "BAT1" ];

  # Checked on the machine being built (builds run with --impure). Pure
  # evaluation can't read /sys, so it reports a desktop.
  isLaptop = !lib.inPureEvalMode && hasBattery "";
in
{
  inherit importAll hasBattery isLaptop;
}
