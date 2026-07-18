{
  description = "maxmustermann's NixOS config";

  inputs = {
    # ================================ ONE-LINERS ================================
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    claude-code-nix.url = "github:sadjow/claude-code-nix";
    claude-desktop.url = "github:aaddrick/claude-desktop-debian";

    # ================================ DEPENDS-ON ================================
    silent-sddm = {
      url = "github:uiriansan/SilentSDDM";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # ================================ LOCAL-ONLY ================================
    crun.url = "path:./Scripts/CRun";
    ltree.url = "path:./Scripts/LTree";
    casket.url = "path:./Scripts/Casket";

    # ================================ INFO-ABOUT ================================
    # CLAUDE-DESKTOP | CLAUDE-COWORK
    # > aaddrick's flake (not k3d3's) -- it repackages Anthropic's official
    # > first-party Linux .deb, which is what actually has the Cowork tab;
    # > k3d3's is an older, separately-patched build with no Cowork support.
  };

  outputs =
    { ... }@inputs:
    {
      nixosConfigurations.maxmustermann = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./Nixos/configuration.nix
          inputs.home-manager.nixosModules.home-manager
          inputs.silent-sddm.nixosModules.default
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.maxmustermann = import ./Nixos/home.nix;
          }
        ];
      };
    };
}
