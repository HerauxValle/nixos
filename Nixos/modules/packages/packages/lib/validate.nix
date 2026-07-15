{ lib }:

# Returns true (via lib.assertMsg) when `default` is a key of the
# `versions` attrset; otherwise throws a descriptive error. Meant to
# be used with `assert` so evaluation is actually forced, e.g.:
#   assert validate packageName versions default;

packageName: versions: default:

lib.assertMsg (builtins.hasAttr default versions) ''
  Package '${packageName}': default version '${default}' is not a key
  in its 'versions' attrset. Add it to 'versions' or change 'default'.
''
