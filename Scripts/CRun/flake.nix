{
  description = "CRun - Rust local runner compilation service";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
    }:
    utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "crun";
          version = "0.1.0";
          src = ./.;

          # Tip: If dependencies change, swap this string with lib.fakeHash
          # to see what string Nix expects next.
          cargoHash = "sha256-VAgmoai/e6P6EZeO1MuBaa2UPYXTe8D0G/xS6R1gSQ8=";
        };
      }
    );
}
