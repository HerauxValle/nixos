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
  source.${packageName} or (throw "Package '${packageName}' does not exist in source '${sourceName}'.")

else if builtins.hasAttr spec inputs then
  (import inputs.${spec} { inherit system; }).${packageName}
    or (throw "Package '${packageName}' does not exist in flake input '${spec}'.")

else
  let
    fetched = builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/${spec}.tar.gz";
  in
  (import fetched { inherit system; }).${packageName}
    or (throw ''
      Package '${packageName}' does not exist in nixpkgs at commit/channel
      '${spec}'. This path is impure and requires `--impure`.
    '')
