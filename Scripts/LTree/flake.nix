{
  description = "LTree - blazing fast recursive tree, line/char counter, JSON exporter";

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
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "ltree";
          version = "0.1.0";
          src = ./.;

          # No -march=native here on purpose: this derivation has to be
          # buildable (and cacheable) on whatever machine runs `nix build`,
          # not just the one that happens to build it first. Drop into
          # `nix develop` and compile with -march=native yourself for a
          # machine-local binary if you want that extra edge.
          buildPhase = ''
            runHook preBuild
            $CC -O3 -std=c11 -Wall -Wextra -o ltree src/ltree.c
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            mkdir -p $out/bin
            cp ltree $out/bin/ltree
            runHook postInstall
          '';

          meta = {
            description = "Recursive directory tree with line/char counts and JSON export";
            mainProgram = "ltree";
          };
        };

        # `nix develop` gives you gdb + valgrind alongside gcc, same
        # toolchain used to verify the shipped binary is leak-free.
        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.gcc
            pkgs.gdb
            pkgs.valgrind
          ];
        };
      }
    );
}
