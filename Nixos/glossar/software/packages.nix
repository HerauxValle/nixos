{ ... }:

# =========================================================================
# EXAMPLES -- every config.vars.environment option, all commented out.
# Same shape as glossar/main/variables.nix, scoped to one module. Schema:
# modules/packages/packages/default.nix. Real values on this machine:
# config/software/packages/{registry,packages}.nix. Logic that resolves
# this registry into environment.systemPackages, writes
# /etc/packages-hash-manifest.json, and defines the packagesHashDiscovery
# activation script (see the "#" / "#<hash>" block below):
# modules/packages/packages/main.nix.
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
  #         # default also exposes two extra names automatically: unsuffixed
  #         # ("somepkg-pure-a") for plain PATH lookups, and "-latest"
  #         # ("somepkg-pure-a-latest") that keeps working if default later
  #         # points at a different key. A key literally named "latest" that
  #         # ISN'T also default is a checked error (would collide with it).
  #         default = "ab.cd.e";
  #       };

  #       # IMPURE OPTION: Using a Raw Commit Hash Directly
  #       # Fast to write without modifying flake.nix, but lacks lockfile pins.
  #       # Requires running evaluations with the `--impure` flag.
  #       somepkg-impure = {
  #         versions = {
  #           "ab.cd.e" = "AbcDef"; # Fetches nixpkgs/archive/AbcDef.tar.gz on the fly
  #         };&
  #         default = "ab.cd.e"; # Exposes "somepkg-impure" unsuffixed on your PATH
  #       };

  #       # PINNING A RAW COMMIT: append "#<hash>"
  #       # Makes the impure option above pure -- no --impure needed. Used
  #       # exactly as written and never re-verified; a wrong hash just
  #       # fails the build the normal way, same as any other mispinned fetch.
  #       somepkg-pinned = {
  #         versions = {
  #           "ab.cd.e" = "AbcDef#sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=";
  #         };
  #         default = "ab.cd.e";
  #       };

  #       # DON'T KNOW THE HASH YET? bare trailing "#", no value after it
  #       # Still needs --impure to build (identical fetch to the impure
  #       # option above -- only difference is this also gets picked up for
  #       # discovery). After a successful --impure rebuild, the real hash
  #       # prints as a red one-liner via the packagesHashDiscovery
  #       # activation script (modules/packages/packages/main.nix):
  #       #   [Packages] Missing hash: somepkg-discover ab.cd.e sha256-...
  #       # Copy that value back in as "#<hash>" above and rebuild -- pinned
  #       # and pure from then on, no more --impure needed for this entry.
  #       somepkg-discover = {
  #         versions = {
  #           "ab.cd.e" = "AbcDef#";
  #         };
  #         default = "ab.cd.e";
  #       };

  #       # CUSTOM ALIAS: append "@<alias>" to a versions key
  #       # Doesn't change what gets fetched or the normal "-ab.cd.e"
  #       # suffixed exposure -- adds one extra, direct PATH name for
  #       # whichever bin/ file is literally named "somepkg-aliased", e.g.
  #       # "somepkg5" runs the exact same binary as "somepkg-aliased-ab.cd.e".
  #       # Alias names must be globally unique across every package
  #       # declared anywhere in this file, not just within one entry --
  #       # a clear eval-time error names the exact duplicate(s) if not.
  #       somepkg-aliased = {
  #         versions = {
  #           "ab.cd.e@somepkg5" = "AbcDef#sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=";
  #         };
  #         default = "ab.cd.e@somepkg5"; # default must name the key in full, "@alias" included
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
