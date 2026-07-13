{
  description = "maxmustermann's NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code-nix.url = "github:sadjow/claude-code-nix";
    silent-sddm = {
      url = "github:uiriansan/SilentSDDM";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crun.url = "path:./Scripts/CRun";
    ltree.url = "path:./Scripts/LTree";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      silent-sddm,
      crun,
      ltree,
      ...
    }@inputs:
    {
      nixosConfigurations.maxmustermann = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./Nixos/configuration.nix
          home-manager.nixosModules.home-manager
          silent-sddm.nixosModules.default
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.maxmustermann = import ./Nixos/home.nix;
          }
        ];
      };
    };
}
