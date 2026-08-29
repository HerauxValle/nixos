# &desc: "Nix flake packaging hlm (hardlink manager) as a stdenv derivation wrapping main.py -- state (metadata.json/imports.json/links/) stays in this checkout, see main.py's STATE_DIR comment."
{
  description = "hlm - hardlink manager: tracks hardlinks created from originals in a JSON store";

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
        packages = {
          default = pkgs.stdenv.mkDerivation {
            pname = "hlm";
            version = "1.0.0";
            src = ./main.py;

            nativeBuildInputs = [ pkgs.makeWrapper ];
            buildInputs = [ pkgs.python3 ];

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall

              mkdir -p $out/bin
              install -m755 $src $out/bin/.hlm-unwrapped
              patchShebangs $out/bin/.hlm-unwrapped
              makeWrapper $out/bin/.hlm-unwrapped $out/bin/hlm

              runHook postInstall
            '';

            meta = {
              description = "Hardlink manager -- tracks hardlinks created from originals, with a short id for later pruning";
              mainProgram = "hlm";
              platforms = pkgs.lib.platforms.linux;
            };
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [ pkgs.python3 ];
        };
      }
    );
}
