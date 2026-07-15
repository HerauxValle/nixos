{ lib }:

# Returns true (via lib.assertMsg) when `default` appears in `versions`;
# otherwise throws a descriptive error. Meant to be used with `assert`
# so evaluation is actually forced, e.g.:
#   assert validate packageName versions default;

packageName: versions: default:

lib.assertMsg (builtins.elem default versions) ''
  Package '${packageName}': default version '${default}' is not listed
  in its 'versions' array. Add it to 'versions' or change 'default'.
''
