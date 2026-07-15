{
  lib,
  wrapSuffixed,
  validate,
  resolveSpec,
}:

# Resolves all derivations for a package declared with `versions`:
# one suffixed wrapper per version label, plus the `default` label's
# derivation again, unsuffixed, for plain PATH access.

{
  sourceName,
  packageName,
  source,
  versions,
  default,
}:

assert validate packageName versions default;

let
  resolveLabel =
    label:
    resolveSpec {
      inherit sourceName packageName source;
      spec = versions.${label};
    };

  suffixed = lib.mapAttrsToList (label: _: wrapSuffixed (resolveLabel label) label) versions;

  unsuffixedDefault = resolveLabel default;
in
suffixed ++ [ unsuffixedDefault ]
