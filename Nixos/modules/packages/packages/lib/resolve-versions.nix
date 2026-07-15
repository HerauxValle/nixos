{ wrapSuffixed, validate }:

# Resolves all derivations for a package declared with `versions`:
# one suffixed wrapper per entry in `versions`, plus the `default`
# entry's derivation again, unsuffixed, for plain PATH access.

{
  sourceName,
  packageName,
  source,
  versionOverrides,
  versions,
  default,
}:

assert validate packageName versions default;

let
  resolveVersion =
    v:
    if v == "latest" then
      source.${packageName}
        or (throw "Package '${packageName}' does not exist in source '${sourceName}'.")
    else
      versionOverrides.${sourceName}.${packageName}.${v} or (throw ''
        No pinned override for '${packageName}' version '${v}' in source
        '${sourceName}'. Add it to
        versionOverrides.${sourceName}.${packageName}."${v}".
      '');

  suffixed = map (v: wrapSuffixed (resolveVersion v) v) versions;

  unsuffixedDefault = resolveVersion default;
in
suffixed ++ [ unsuffixedDefault ]
