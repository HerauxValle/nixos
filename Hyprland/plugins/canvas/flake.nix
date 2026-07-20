# &desc: "Dev-only flake for the canvas plugin -- standalone nix build/develop, not how the real system build wires this in (see DESIGN.md)."
{
  description = "canvas -- infinite canvas per Hyprland workspace (dev convenience flake; the real system build wires this in via a local path in Nixos/modules/hyprland/plugins/default.nix, not this flake)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      # Standalone build for iterating without a full system rebuild.
      # Deliberately mirrors mkPlugin's own approach (build against
      # pkgs.hyprland.stdenv for ABI match) -- but note this flake pins its
      # own nixpkgs, so this is only a close approximation of the real
      # system build, not a substitute for testing through it.
      packages.${system}.default = pkgs.hyprland.stdenv.mkDerivation {
        pname = "hyprland-canvas";
        version = "0-unstable-local";
        src = ./.;
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.hyprland ] ++ pkgs.hyprland.buildInputs;
        dontStrip = true;
      };

      # `nix develop` for editor tooling (clangd, compile_commands.json via
      # bear) while working on the plugin.
      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ self.packages.${system}.default ];
        packages = [ pkgs.clang-tools pkgs.bear ];
      };
    };
}
