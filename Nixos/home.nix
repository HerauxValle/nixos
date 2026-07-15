{ osConfig, ... }:

{
  home.stateVersion = osConfig.vars.stateVersion;
  home.username = osConfig.vars.username;
  home.homeDirectory = osConfig.vars.homeDirectory;

  imports = [
    ./home/apps.nix
    ./home/shells.nix
    ./home/theming.nix
  ];

  programs.home-manager.enable = false;
}
