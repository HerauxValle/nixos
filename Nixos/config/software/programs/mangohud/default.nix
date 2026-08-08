# &desc: "MangoHud config imports -- enable.nix (session toggle) plus settings.nix (HUD layout/metrics)."

{ ... }:

{
  imports = [
    ./enable.nix
    ./settings.nix
  ];
}
