
{ }:

# Resolves the plain, unsuffixed derivation for a package that declares
# no `versions` (identical to the original, pre-versioning behavior).

{
  sourceName,
  packageName,
  source,
}:

source.${packageName} or (throw ''
  Package '${packageName}' does not exist in source '${sourceName}'.
'')
