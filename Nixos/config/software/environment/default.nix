# &desc: "Personal PATH/environment config imports -- paths, repos, scripts, shells, venvs."

{ ... }:

{
  imports = [
    ./paths.nix
    ./repos.nix
    ./scripts.nix
    ./shells.nix
    ./venvs.nix
  ];
}
