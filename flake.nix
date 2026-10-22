{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
    nixos-x86-64-v3-repo.url = "github:HenrikDK2/nixos-x86-64-v3-repo";
    look.url = "github:kunkka19xx/look";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixos-x86-64-v3-repo, home-manager, ... }:
    let
      lib = nixpkgs.lib;
      helpers = import ./lib { inherit lib; };
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs helpers; };

        modules = [
          ./system/configuration.nix
          nixos-x86-64-v3-repo.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              backupFileExtension = "backup";
              extraSpecialArgs = { inherit inputs helpers; };
            };
          }
        ];
      };
    };
}
