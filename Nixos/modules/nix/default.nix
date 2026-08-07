# &desc: "Nix configuration -- garbage collection, automatic store dedup with stats, and experimental features (flakes, nix-command)."

{ ... }:

{
  imports = [
    ./gc.nix
    ./optimise.nix
    ./settings.nix
  ];
}
