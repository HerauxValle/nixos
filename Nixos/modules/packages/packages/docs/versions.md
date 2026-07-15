# packages/ — versioning model

## Files

default.nix options schema (sources, packages, versionOverrides)
main.nix resolution entrypoint -> environment.systemPackages
lib/default.nix wires up the helpers below
lib/resolve-default.nix plain unsuffixed resolution (no versions declared)
lib/resolve-versions.nix multi-version resolution (versions declared)
lib/wrap-suffixed.nix builds a version-suffixed bin/ wrapper derivation
lib/validate.nix checks that `default` is a member of `versions`

## Per-package schema

<pkg> = {
versions = [ "latest" "5.9.4" ... ]; # list of str, default []
default = "latest"; # str, default "latest"
};

## Resolution rules

1. versions == [ ] (default)
   -> identical to the original, pre-versioning behavior. The plain
   derivation from `source.<pkg>` is installed unsuffixed. `default`
   is never read or validated.

2. versions != [ ]
   -> `default` MUST be an element of `versions`, or evaluation throws
   a descriptive error (lib/validate.nix).
   -> For every entry `v` in `versions`: - v == "latest" -> base derivation is `source.<pkg>` (whatever
   your main flake input currently provides) - v == "<other>" -> base derivation is looked up in
   versionOverrides.<source>.<pkg>.<v>,
   throwing a clear error if missing
   Each of these base derivations is wrapped (lib/wrap-suffixed.nix)
   so every file in its bin/ is exposed as "<file>-<v>".
   -> Whichever entry equals `default` is ALSO installed as its plain,
   unwrapped, unsuffixed derivation, so `default` behaves exactly
   like the no-versioning case on PATH.

## Worked example

swift = { versions = [ "latest" "5.9.4" ]; default = "latest"; };

Produces on PATH:
swift, swiftc -> source.pkgs.swift (unsuffixed, default)
swift-latest, swiftc-latest -> source.pkgs.swift (suffixed, redundant but harmless)
swift-5.9.4, swiftc-5.9.4 -> versionOverrides.pkgs.swift."5.9.4"

## Populating versionOverrides

versionOverrides is intentionally generic: it just needs to end up as
sourceName -> packageName -> version -> derivation
It doesn't matter whether that derivation comes from a second pinned
nixpkgs flake input, an overlay, or something built by hand. Typical
pattern for a second flake input:

# flake.nix

inputs.nixpkgs-swift-5-9-4.url = "github:NixOS/nixpkgs/<commit>";

# somewhere imported alongside your packages.nix

{ inputs, system, ... }:
{
config.vars.environment.versionOverrides.pkgs.swift."5.9.4" =
(import inputs.nixpkgs-swift-5-9-4 { inherit system; }).swift;
}

## Known limitation

wrap-suffixed.nix only re-exposes bin/\*. man pages, share/, lib/, etc.
from a suffixed version are not exposed under the suffixed derivation.
The unsuffixed `default` entry is the plain, unwrapped derivation, so
it keeps all of those outputs as normal.
