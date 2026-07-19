# &desc: "Personal PATH/environment config imports -- scripts, shells, venvs."

{ ... }:

{
  imports = [
    ./scripts.nix
    ./shells.nix
    ./venvs.nix
  ];
}
