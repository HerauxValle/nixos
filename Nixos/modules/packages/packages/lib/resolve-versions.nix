{
  lib,
  wrapSuffixed,
  validate,
  resolveSpec,
}:

# Resolves all derivations for a package declared with `versions`:
# one suffixed wrapper per version label, plus the `default` label's
# derivation again, unsuffixed, for plain PATH access.
#
# Returns `{ drvs; manifestEntries; }` -- manifestEntries carries any
# bare-"#" hash-discovery entries (see resolve-spec.nix), nulls already
# filtered out, entries de-duplicated by `spec` (the same label can be
# resolved twice -- once suffixed, once as `default`).

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
      version = label;
      spec = versions.${label};
    };

  resolvedByLabel = lib.mapAttrsToList (label: _: {
    inherit label;
    result = resolveLabel label;
  }) versions;
  resolvedDefault = resolveLabel default;

  suffixedDrvs = map (r: wrapSuffixed r.result.drv r.label) resolvedByLabel;
in
{
  drvs = suffixedDrvs ++ [ resolvedDefault.drv ];
  manifestEntries = lib.unique (
    lib.filter (e: e != null) (
      (map (r: r.result.manifestEntry) resolvedByLabel) ++ [ resolvedDefault.manifestEntry ]
    )
  );
}
