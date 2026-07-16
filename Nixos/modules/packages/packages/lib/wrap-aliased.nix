{ pkgs }:

# Wraps a derivation so its "<packageName>" file in bin/ (and only that
# one file -- not every file in bin/, unlike wrap-suffixed.nix) is
# additionally exposed as a plain top-level "<alias>" name. Deliberately
# matches on the file literally named like the package rather than
# `meta.mainProgram` -- that field isn't always set (hit this gap with
# `xz` earlier), whereas "the file named like the package" is always
# well-defined.

drv: packageName: alias:

pkgs.runCommand "${drv.pname or drv.name}-alias-${alias}" { } ''
  mkdir -p "$out/bin"
  if [ -e "${drv}/bin/${packageName}" ]; then
    ln -s "${drv}/bin/${packageName}" "$out/bin/${alias}"
  fi
''
