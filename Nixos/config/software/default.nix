# &desc: "Software config imports -- programs (VSCode), services (Polkit), scripts, shells, venvs, and packages submodules."

{ ... }:

{
  imports = [
    ./programs
    ./services.nix
    ./scripts.nix
    ./shells.nix
    ./venvs.nix
    ./packages
  ];
}
