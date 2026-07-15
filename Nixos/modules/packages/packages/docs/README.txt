packages/ — declarative package installation with optional
per-package version coexistence.

BASIC USE (no versioning)

  config.vars.environment.packages.pkgs.vivaldi = { };

Resolves to `pkgs.vivaldi`, unsuffixed, on PATH. Nothing else needed.

VERSIONED USE

  config.vars.environment.packages.pkgs.swift = {
    versions = {
      "latest" = "";
      "5.9.4"  = "nixpkgs-old-swift";
      "5.5.0"  = "b5aa0fb";
    };
    default = "latest";
  };

Each key in `versions` is a label of your choosing (doesn't have to be
a real version number). Each value is a "spec" string saying where
that label's build comes from:

  ""  or  "latest"     -> the package from the normal source, i.e.
                           `sources.pkgs.swift` (pure, fast, no extra
                           setup)

  a flake input name    -> resolved as
                           `(import inputs.<name> { inherit system; }).swift`
                           Requires the input to already be declared
                           in flake.nix, e.g.:
                             inputs.nixpkgs-old-swift.url =
                               "github:NixOS/nixpkgs/<commit>";
                           Pure, fast, no copy-pasting hashes at eval
                           time — the pin lives in flake.lock.

  anything else          -> treated as a raw commit hash or channel
                           string, e.g. "b5aa0fb" or
                           "26.11.20260629.b5aa0fb". Fetched on the fly
                           with `builtins.fetchTarball`. Impure — you
                           need `nixos-rebuild switch --impure` (or
                           equivalent) for this branch to evaluate.
                           No flake.nix edits needed, but also no
                           lockfile pin, so re-fetches can drift.

Every entry in `versions` gets built and exposed suffixed with its
label, e.g. `swift-5.9.4`, `swiftc-5.9.4` (every file in that build's
bin/, not just one hardcoded name). Whichever label is named in
`default` is *additionally* exposed unsuffixed — `swift`, `swiftc` —
so plain PATH lookups keep working. `default` must be a key that
actually exists in `versions`; if it doesn't, evaluation fails with a
clear error (lib/validate.nix) instead of silently picking something.

Leaving `versions = { }` (the default) skips all of this and behaves
exactly like the basic, no-versioning case above.

WHY VERSION LABELS AREN'T ALWAYS ENOUGH

Two builds can report the same version number but behave differently
(e.g. swift 5.10.1 built from commit A works, the same 5.10.1 from
commit B doesn't). That's why a version label maps to a spec you
control — pin it to a specific flake input or commit rather than
trusting the version string alone to mean one exact build.

REQUIRED WIRING IN flake.nix

`inputs` and `system` must reach this module via specialArgs, since
the flake-input and raw-commit spec branches need them:

  specialArgs = { inherit inputs; system = "x86_64-linux"; };
  # (or wherever your system string comes from)

FILES

  default.nix              options schema (sources, packages, and the
                            per-package versions/default submodule)
  main.nix                 resolution entrypoint; turns declared
                            packages into environment.systemPackages
  lib/default.nix           wires up the helper functions below
  lib/resolve-default.nix   no-versions case (plain, unsuffixed pkg)
  lib/resolve-versions.nix  versions case: suffixed copies + default
  lib/resolve-spec.nix      turns one spec string into a derivation
  lib/validate.nix          checks that default is a key of versions
  lib/wrap-suffixed.nix     builds the suffixed-bin/ wrapper derivation

NOTE: the flake-input and raw-commit spec branches always resolve
through plain top-level `pkgs.<packageName>` in the imported nixpkgs,
regardless of which `sourceName` (e.g. pkgs.kdePackages) the package
was declared under. They don't know how to walk into non-pkgs
sources — only the ""/"latest" branch respects the declared source.
