# &desc: "Packages module schema -- imports programs, repos, scripts, shells, venvs, and packages submodules."

{ ... }:

# installed.nix's package list has no schema/logic split at all -- it's
# purely personal, lives in Nixos/config/packages.nix instead.
{
  imports = [
    ./programs
    ./repos
    ./scripts
    ./shells
    ./venvs
    ./packages
  ];
}
