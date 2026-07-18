# &desc: "Home Manager configuration root -- sets identity from NixOS config and imports home/ subdirectories."

{ osConfig, ... }:

{
  home.stateVersion = osConfig.vars.identity.stateVersion;
  home.username = osConfig.vars.identity.username;
  home.homeDirectory = osConfig.vars.identity.homeDirectory;

  imports = [
    ./home/apps.nix
    ./home/shells.nix
    ./home/theming.nix
  ];

  programs.home-manager.enable = false;
}
