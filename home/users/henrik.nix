{ pkgs, lib, helpers, inputs, ... }:

let
  username = "henrik";

  gitUsername = "HenrikDK2";
  gitEmail = "30632653+HenrikDK2@users.noreply.github.com";
in
{
  users.users.${username} = {
    isNormalUser = true;
    initialPassword = "1234";

    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  home-manager.extraSpecialArgs = {
    inherit gitUsername gitEmail;
  };

  home-manager.users.${username} = {
    home.stateVersion = "26.05";

    imports = lib.flatten [
      (helpers.importAll ../services)
      (helpers.importAll ../modules)
      (helpers.importAll ../programs)
    ];
  };
}
