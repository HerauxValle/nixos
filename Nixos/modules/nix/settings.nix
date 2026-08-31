# &desc: "Core nix settings -- allow unfree packages, accept Android SDK license, enable experimental features (flakes, nix-command)."

{ ... }:

{
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.android_sdk.accept_license = true;
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  # programs.nix-ld now lives in modules/packages/programs/programs.nix.
}
