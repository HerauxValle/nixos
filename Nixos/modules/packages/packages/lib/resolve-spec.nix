{ inputs, system }:

# Resolves one version label's spec string into a derivation:
#   ""/"latest"    -> `source.<packageName>` (the declared default source)
#   <flake input>  -> `pkgs.<packageName>` from that pinned flake input
#   anything else  -> `pkgs.<packageName>` fetched from that commit or
#                      channel string via fetchTarball. Impure — the
#                      caller needs `--impure` for this branch.
#
# The flake-input and raw-commit branches always resolve through a
# plain top-level `pkgs.<packageName>`, regardless of `sourceName` —
# they don't know about non-`pkgs` sources like `pkgs.kdePackages`.

{
  sourceName,
  packageName,
  source,
  spec,
}:

if spec == "" || spec == "latest" then
  source.${packageName}
    or (throw "Package '${packageName}' does not exist in source '${sourceName}'.")

else if builtins.hasAttr spec inputs then
  (import inputs.${spec} { inherit system; }).${packageName}
    or (throw "Package '${packageName}' does not exist in flake input '${spec}'.")

else
  let
    # 1. Split the string by dots (e.g., "26.11.20260629.b5aa0fb" -> ["26" "11" "20260629" "b5aa0fb"])
    parts = builtins.filter builtins.isString (builtins.split "\\." spec);

    # 2. Extract the last element (the git commit hash, or the original string if no dots existed)
    commitOrBranch = builtins.elemAt parts (builtins.length parts - 1);

    fetched = builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/${commitOrBranch}.tar.gz";
  in
  (import fetched { inherit system; }).${packageName} or (throw ''
    Package '${packageName}' does not exist in nixpkgs at commit/channel
    '${commitOrBranch}' (resolved from '${spec}'). This path is impure and requires `--impure`.
  '')
