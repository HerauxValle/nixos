# &desc: "Full version resolver -- suffixed/aliased wrappers per key, default/latest automatic names, manifest entries for hash discovery."

{
  lib,
  wrapSuffixed,
  wrapAliased,
  validate,
  resolveSpec,
}:

# Resolves all derivations for a package declared with `versions`:
# one suffixed wrapper per version key, plus the `default` key's
# derivation again both unsuffixed (plain PATH access) and suffixed
# "-latest" (so whichever version is `default` is always reachable
# under a name that doesn't change when `default` is repointed later).
#
# A `versions` key may carry an optional "@<alias>" suffix, e.g.
# "5.10.1@swift5" -- doesn't change what gets fetched (`versions.${key}`
# is still looked up by the raw, full key), only adds a second, direct
# PATH exposure for the one bin/ file matching `packageName` (see
# wrap-aliased.nix) alongside the normal "-<version>" suffixed one,
# which is built from the part before "@" and therefore unaffected by
# whether an alias is present. `default` still names a raw key exactly
# as before -- if you want an aliased key to also be `default`, name it
# in full, "@<alias>" included.
#
# Returns `{ drvs; manifestEntries; aliasNames; }` -- manifestEntries
# carries any bare-"#" hash-discovery entries (see resolve-spec.nix),
# nulls already filtered out, entries de-duplicated by `spec` (the same
# key can be resolved twice -- once suffixed, once as `default`).
# aliasNames is the flat list of every "@<alias>" declared by this
# package, for main.nix to check global uniqueness across all packages.

{
  sourceName,
  packageName,
  source,
  versions,
  default,
}:

assert validate packageName versions default;

let
  parseKey =
    key:
    let
      parts = lib.splitString "@" key;
    in
    assert lib.assertMsg (
      lib.length parts <= 2
    ) "Package '${packageName}': version key '${key}' has more than one '@' -- expected '<version>' or '<version>@<alias>'.";
    {
      version = lib.head parts;
      alias = if lib.length parts > 1 then lib.elemAt parts 1 else null;
    };

  resolveKey =
    key:
    let
      parsed = parseKey key;
      resolved = resolveSpec {
        inherit sourceName packageName source;
        version = parsed.version;
        spec = versions.${key};
      };
    in
    { inherit key; } // parsed // resolved;

  resolvedByKey = lib.mapAttrsToList (key: _: resolveKey key) versions;
  resolvedDefault = resolveKey default;

  suffixedDrvs = map (r: wrapSuffixed r.drv r.version) resolvedByKey;

  aliasedDrvs = map (r: wrapAliased r.drv packageName r.alias) (
    lib.filter (r: r.alias != null) resolvedByKey
  );

  latestDrv = wrapSuffixed resolvedDefault.drv "latest";
in
# A real version key literally named "latest" would produce its own
# "-latest" suffix too (same as any other key), colliding with the
# automatic one above unless it's also what `default` points at.
assert lib.assertMsg (
  !(lib.any (r: r.version == "latest" && r.key != default) resolvedByKey)
) "Package '${packageName}': a version key literally named 'latest' conflicts with the automatic '<package>-latest' alias for whatever 'default' points to (currently '${default}'). Rename that key or set default to it.";
{
  drvs = suffixedDrvs ++ aliasedDrvs ++ [
    latestDrv
    resolvedDefault.drv
  ];
  manifestEntries = lib.unique (
    lib.filter (e: e != null) (
      (map (r: r.manifestEntry) resolvedByKey) ++ [ resolvedDefault.manifestEntry ]
    )
  );
  aliasNames = lib.filter (a: a != null) (map (r: r.alias) resolvedByKey);
}
