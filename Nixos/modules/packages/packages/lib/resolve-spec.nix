{ inputs, system, lib }:

# Resolves one version label's spec string into a derivation:
#   ""/"latest"    -> `source.<packageName>` (the declared default source)
#   <flake input>  -> `pkgs.<packageName>` from that pinned flake input
#   anything else  -> `pkgs.<packageName>` fetched from that commit or
#                      channel string via fetchTarball. The commit/channel
#                      part may carry a `#<hash>` suffix:
#                        no "#" at all  -> unpinned fetchTarball. Impure —
#                                          needs `--impure`. Unchanged,
#                                          long-standing behavior; prints
#                                          a `builtins.trace` banner.
#                        "#<hash>"      -> pinned fetchTarball, pure, no
#                                          `--impure` needed. Used as-is,
#                                          never independently verified —
#                                          if it's wrong, Nix's own build
#                                          fails on it, same as any other
#                                          mispinned fetch.
#                        "#" (nothing
#                        after it)      -> unpinned fetchTarball, same as
#                                          no "#" at all (still needs
#                                          `--impure`, no eval-time banner)
#                                          but ALSO reported in
#                                          `manifestEntry` below, so
#                                          main.nix can collect it into a
#                                          manifest for the
#                                          system.activationScripts hash
#                                          -discovery step (see main.nix)
#                                          — that's the only place the
#                                          real hash gets printed cleanly,
#                                          since nothing in the Nix
#                                          expression language can read a
#                                          builtin fetch failure's hash
#                                          back out for reformatting.
#
# Returns `{ drv; manifestEntry; }` — manifestEntry is null except for
# the bare "#" case described above.
#
# The flake-input and raw-commit branches always resolve through a
# plain top-level `pkgs.<packageName>`, regardless of `sourceName` —
# they don't know about non-`pkgs` sources like `pkgs.kdePackages`.

{
  sourceName,
  packageName,
  source,
  version,
  spec,
}:

if spec == "" || spec == "latest" then
  {
    drv =
      source.${packageName}
        or (throw "Package '${packageName}' does not exist in source '${sourceName}'.");
    manifestEntry = null;
  }

else if builtins.hasAttr spec inputs then
  {
    drv =
      (import inputs.${spec} { inherit system; }).${packageName}
        or (throw "Package '${packageName}' does not exist in flake input '${spec}'.");
    manifestEntry = null;
  }

else
  let
    # 1. Split off the optional "#<hash>" suffix first. No "#" at all ->
    #    hashParts has one element. "#<hash>" or a bare trailing "#" both
    #    split into two elements, the second being the hash (empty
    #    string for a bare "#").
    hashParts = builtins.filter builtins.isString (builtins.split "#" spec);
    versionSpec = builtins.elemAt hashParts 0;
    hasHashMarker = builtins.length hashParts > 1;
    givenHash = builtins.elemAt hashParts 1;
    isBareMarker = hasHashMarker && givenHash == "";
    isPinned = hasHashMarker && !isBareMarker;

    # 2. Split the version part by dots (e.g., "26.11.20260629.b5aa0fb" -> ["26" "11" "20260629" "b5aa0fb"])
    parts = builtins.filter builtins.isString (builtins.split "\\." versionSpec);

    # 3. Extract the last element (the git commit hash, or the original string if no dots existed)
    commitOrBranch = builtins.elemAt parts (builtins.length parts - 1);

    url = "https://github.com/NixOS/nixpkgs/archive/${commitOrBranch}.tar.gz";

    fetched =
      if isPinned then
        builtins.fetchTarball { inherit url; sha256 = givenHash; }
      else if isBareMarker then
        builtins.fetchTarball url
      else
        let
          border = "!! ---------------------------------------------------------------- !!";
        in
        builtins.trace ''

          ${border}
          !! [Packages] ${packageName} ${version} (spec '${spec}')
          !! NO HASH PINNED — fetching '${commitOrBranch}' impurely. Needs
          !! `nixos-rebuild switch --impure` (or equivalent) to evaluate.
          !! To make this pure, add '#<hash>' after the version string, or
          !! a bare trailing '#' to discover the hash without a Nix error
          !! (see /etc/packages-hash-manifest.json after an impure build).
          ${border}
        '' (builtins.fetchTarball url);
  in
  {
    drv =
      (import fetched { inherit system; }).${packageName}
        or (throw ''
          Package '${packageName}' does not exist in nixpkgs at commit/channel
          '${commitOrBranch}' (resolved from '${spec}').
        '');
    manifestEntry =
      if isBareMarker then
        {
          name = packageName;
          inherit version spec;
          sourcePath = "${fetched}";
        }
      else
        null;
  }
