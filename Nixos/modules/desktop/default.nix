# &desc: "Desktop module root -- imports display server setup, graphics, theming, and default application configuration."

{ ... }:

{
  imports = [
    ./desktop.nix
    ./graphics.nix
    ./theming.nix
    ./defaults
  ];
}
