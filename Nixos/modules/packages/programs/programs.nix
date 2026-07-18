
{ config, ... }:

let
  cfg = config.vars.packages.programs;
in

# All NixOS system-level programs.* options, assembled from config.vars.packages.programs
# so every entry has an obvious place to go (Nixos/modules/packages/programs/default.nix
# for the schema, Nixos/config/programs.nix for personal picks) instead of
# sprouting its own top-level programs.<x> = ...; line.
{
  programs = {
    fish.enable = cfg.fish.enable;

    hyprland = {
      enable = cfg.hyprland.enable;
      withUWSM = cfg.hyprland.withUWSM;
      xwayland.enable = cfg.hyprland.xwayland;
    };

    steam = {
      enable = cfg.steam.enable;
      remotePlay.openFirewall = cfg.steam.remotePlayOpenFirewall;
      dedicatedServer.openFirewall = cfg.steam.dedicatedServerOpenFirewall;
      localNetworkGameTransfers.openFirewall = cfg.steam.localNetworkGameTransfersOpenFirewall;
    };

    gamemode.enable = cfg.gamemode.enable;
    gamescope.enable = cfg.gamescope.enable;

    silentSDDM = {
      enable = cfg.silentSDDM.enable;
      theme = cfg.silentSDDM.theme;
      backgrounds = if cfg.silentSDDM.wallpaper == null then { } else { inherit (cfg.silentSDDM) wallpaper; };
      settings =
        if cfg.silentSDDM.wallpaper == null then
          { }
        else
          {
            "LoginScreen".background = builtins.baseNameOf cfg.silentSDDM.wallpaper;
            "LockScreen".background = builtins.baseNameOf cfg.silentSDDM.wallpaper;
          };
    };

    direnv.enable = cfg.direnv.enable;
    direnv.silent = cfg.direnv.silent;

    nix-ld.enable = cfg.nixLd.enable;
  };

  # Some programs.* options only exist under home-manager, not as NixOS
  # system options -- reached through home-manager.users.<name>.programs
  # instead, same as packages/shells/shells.nix does elsewhere.
  home-manager.users.${config.vars.identity.username}.programs = {
    fresh-editor = {
      enable = cfg.freshEditor.enable;
      defaultEditor = cfg.freshEditor.defaultEditor;
      extraPackages = cfg.freshEditor.extraPackages;
    };
  };
}
