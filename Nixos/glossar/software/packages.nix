{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.environment option, all commented out.
# Same shape as glossar/main/variables.nix, scoped to one module. Schema:
# modules/packages/packages/default.nix. Real values on this machine:
# config/software/packages/{registry,packages}.nix. Logic that resolves
# this registry into environment.systemPackages:
# modules/packages/packages/config.nix.
#
# Packages are declared in two stages:
#
#   sources  -> where packages come from (pkgs, pkgs.kdePackages,
#               flake inputs, wrapped derivations, custom collections,
#               etc.)
#
#   packages -> which packages to install from each source.
#
# Splitting package definitions from package selection keeps user config
# free of `let`, `with`, duplicated package expressions and long flake
# references. Complex or wrapped derivations only need to be declared
# once under `sources` and can then be referenced by name just like any
# normal nixpkgs package.
#
# Package values are empty attribute sets rather than booleans to leave
# room for future per-package options (overrides, conditions, metadata,
# platform restrictions, etc.) without changing the schema.
#
# NOT imported anywhere -- never evaluated, purely a copy-paste
# reference. Copy a block (or a line out of one) into
# config/software/packages/{registry,packages}.nix and uncomment it
# there to actually set it.
# =========================================================================

{
  # config.vars.environment = {

  #   # --- package registries --------------------------------------------

  #   sources = {

  #     # Plain nixpkgs package collections
  #     pkgs = pkgs;
  #     kde = pkgs.kdePackages;
  #     qt5 = pkgs.libsForQt5;
  #     qt6 = pkgs.qt6Packages;
  #     python = pkgs.python3Packages;

  #     # Collections built from arbitrary derivations
  #     custom = {
  #       claudeCode = inputs.claude-code-nix.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
  #       mybarBackend = pkgs.callPackage ../../../Quickshell/MyBar/backend.nix { };

  #       kittyWrapped = pkgs.kitty.overrideAttrs (old: {
  #         nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
  #         postFixup = (old.postFixup or "") + ''
  #           wrapProgram $out/bin/kitty \
  #             --prefix LD_LIBRARY_PATH : ${
  #               pkgs.lib.makeLibraryPath [ pkgs.libxkbcommon ]
  #             }
  #         '';
  #       });
  #     };

  #     # PURE OPTION B SOURCE: Map a custom source to a pinned flake input.
  #     # This bypasses the versions submodule entirely to expose the package.
  #     # nixpkgs-abcdef = import inputs.nixpkgs-abcdef { inherit system; };

  #   };

  #   # --- packages to install -------------------------------------------

  #   packages = {

  #     # Install from pkgs
  #     pkgs = {
  #       git = { };
  #       curl = { };
  #       python3 = { };
  #       neovim = { };

  #       # -----------------------------------------------------------------
  #       # SPECIFYING VERSION "ab.cd.e" FROM COMMIT "AbcDef" OF NIXPKGS
  #       # -----------------------------------------------------------------

  #       # PURE OPTION A: Using a Flake Input Spec (Recommended)
  #       # Safe, reproducible, fast, and does not require `--impure`.
  #       #
  #       # 1. In your flake.nix, register the specific commit as an input:
  #       #    inputs.nixpkgs-abcdef.url = "github:NixOS/nixpkgs/AbcDef";
  #       #
  #       # 2. Reference that input name ("nixpkgs-abcdef") as the spec string:
  #       somepkg-pure-a = {
  #         versions = {
  #           "ab.cd.e" = "nixpkgs-abcdef"; # maps to inputs.nixpkgs-abcdef
  #         };
  #         default = "ab.cd.e"; # Exposes "somepkg-pure-a" unsuffixed on your PATH
  #       };

  #       # IMPURE OPTION: Using a Raw Commit Hash Directly
  #       # Fast to write without modifying flake.nix, but lacks lockfile pins.
  #       # Requires running evaluations with the `--impure` flag.
  #       somepkg-impure = {
  #         versions = {
  #           "ab.cd.e" = "AbcDef"; # Fetches nixpkgs/archive/AbcDef.tar.gz on the fly
  #         };
  #         default = "ab.cd.e"; # Exposes "somepkg-impure" unsuffixed on your PATH
  #       };
  #     };

  #     # PURE OPTION B: Using a custom source bound to a flake input
  #     # If you prefer to bypass version suffixing entirely, reference a source
  #     # declared directly from the flake input (defined in `sources` above).
  #     # nixpkgs-abcdef = {
  #     #   somepkg = { }; # Evaluates to sources.nixpkgs-abcdef.somepkg
  #     # };

  #     # Install from pkgs.kdePackages
  #     kde = {
  #       dolphin = { };
  #       breeze = { };
  #       gwenview = { };
  #     };

  #     # Install from pkgs.python3Packages
  #     python = {
  #       pip = { };
  #     };

  #     # Install from custom package registry
  #     custom = {
  #       claudeCode = { };
  #       kittyWrapped = { };
  #     };

  #   };

  # };

  # --- package resolution -------------------------------------------------
  # Every packages.<source> entry must have a matching source under
  # config.vars.environment.sources.<source>. Each package key is then
  # resolved automatically from that source, e.g.
  #
  #   packages.kde.dolphin
  #
  # becomes
  #
  #   sources.kde.dolphin
  #
  # during evaluation. Unknown sources or missing package names abort
  # the build with a descriptive error instead of being silently ignored.
}
