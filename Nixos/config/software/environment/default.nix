# &desc: "Personal PATH/environment config imports -- repos, scripts, shells, venvs."

{ ... }:

{
  imports = [
    ./repos.nix
    ./scripts.nix
    ./shells.nix
    ./venvs.nix
  ];
}
