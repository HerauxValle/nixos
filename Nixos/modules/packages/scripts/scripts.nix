# &desc: "Script wrapping logic -- copies folder to store, symlinks file on PATH, filters nulls from skipped entries."

{ config, pkgs, lib, ... }:

let

  scripts = config.vars.packages.scripts;

  # Copies the script's whole containing folder into the store (so any
  # sibling files it sources relative to itself keep resolving) and
  # symlinks just that one file onto PATH as `name`.

  wrapScript = name: path:

    if builtins.pathExists path then

      pkgs.runCommand name { } ''

        mkdir -p $out/opt $out/bin
        cp -r ${dirOf path} $out/opt/src
        chmod +x "$out/opt/src/${baseNameOf path}"
        ln -s "$out/opt/src/${baseNameOf path}" "$out/bin/${name}"

      ''
    else
      lib.warn "modules/packages/scripts: '${name}' skipped -- ${toString path} does not exist (typo in dir/include?)" null;

  wrapEntry = { dir, include }:
    lib.mapAttrsToList (fname: cmdName: wrapScript cmdName (dir + "/${fname}")) include;

in

{
  environment.systemPackages =
    lib.filter (p: p != null) (lib.concatMap wrapEntry scripts);
}
