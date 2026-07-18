{
  description = "maxmustermann's NixOS config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code-nix.url = "github:sadjow/claude-code-nix";
    claude-desktop.url = "github:k3d3/claude-desktop-linux-flake";
    silent-sddm = {
      url = "github:uiriansan/SilentSDDM";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crun.url = "path:./Scripts/CRun";
    ltree.url = "path:./Scripts/LTree";
    casket.url = "path:./Scripts/Casket";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      silent-sddm,
      crun,
      ltree,
      casket,
      claude-desktop,
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
