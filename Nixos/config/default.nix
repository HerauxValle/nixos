{ ... }:

{
  imports = [
    ./customized.nix
    ./excludes.nix
    ./packages.nix
    ./programs.nix
    ./scripts.nix
    ./self-hosted
    ./shells.nix
    ./services.nix
  ];
}
