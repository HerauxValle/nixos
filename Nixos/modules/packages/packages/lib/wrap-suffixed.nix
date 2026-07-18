
{ pkgs }:

# Wraps a derivation so every file in its bin/ directory is symlinked
# under a "<name>-<suffix>" name, allowing multiple versions of the
# same package to coexist on PATH without collisions.

drv: suffix:

pkgs.runCommand "${drv.pname or drv.name}-${suffix}" { } ''
  mkdir -p "$out/bin"
  if [ -d "${drv}/bin" ]; then
    for f in "${drv}/bin"/*; do
      ln -s "$f" "$out/bin/$(basename "$f")-${suffix}"
    done
  fi
''
