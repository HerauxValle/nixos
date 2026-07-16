{ lib, ... }:

# Which of NixOS's own programs.* toggles this repo turns on -- same
# schema/customization split as everywhere else. Entries that the REST of
# this repo already assumes regardless of who's cloning it (fish is the
# shell packages/shells.nix's direnv integration targets, hyprland is what
# modules/hyprland, Hyprland/, and Quickshell/MyBar are all built against,
# direnv/nix-ld are infra packages/shells.nix and nix/settings.nix rely on)
# get a real generic default here, same reasoning as scripts/default.nix's
# pacnix entry. Genuinely personal picks (the gaming stack, silentSDDM's
# theme/wallpaper, the editor) have no default -- their one real definition
# lives in Nixos/config/programs.nix. Logic that reads these lives in
# ./programs.nix, imported below.
{
  imports = [ ./programs.nix ];

  options.vars.programs = {
    fish.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "programs.fish.enable -- also the account's login shell (modules/system/users/users.nix).";
    };

    hyprland = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "programs.hyprland.enable.";
      };
      withUWSM = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "programs.hyprland.withUWSM.";
      };
      xwayland = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "programs.hyprland.xwayland.enable.";
      };
    };

    direnv = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "programs.direnv.enable -- packages/shells' declarative per-directory shells depend on it.";
      };
      silent = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''programs.direnv.silent -- suppresses direnv's "loading/using/export" status lines.'';
      };
    };

    nixLd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "programs.nix-ld.enable.";
    };

    # --- below: no generic default, opinionated personal picks ---

    steam = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "programs.steam.enable.";
      };
      remotePlayOpenFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "programs.steam.remotePlay.openFirewall.";
      };
      dedicatedServerOpenFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "programs.steam.dedicatedServer.openFirewall.";
      };
      localNetworkGameTransfersOpenFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "programs.steam.localNetworkGameTransfers.openFirewall.";
      };
    };

    # Bumps CPU governor/priority while a game runs. Use via `gamemoderun %command%` in Steam launch options.
    gamemode.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "programs.gamemode.enable.";
    };

    # Micro-compositor for FSR upscaling / frame limiting / fullscreen fixes. Use via `gamescope ... -- %command%`.
    gamescope.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "programs.gamescope.enable.";
    };

    silentSDDM = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "programs.silentSDDM.enable -- sets up services.displayManager.sddm itself (theme, wayland.enable, extraPackages etc.), see flake.nix for the silent-sddm input.";
      };
      theme = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = "programs.silentSDDM.theme.";
      };
      # SDDM login/lock background. null = no custom background wired in.
      # Filename after copy is the basename of this path regardless of the
      # backgrounds attrset key -- see silent-sddm's nix/package.nix.
      wallpaper = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Login/lock background, wired into programs.silentSDDM.backgrounds/settings.";
      };
    };

    dconf.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "programs.dconf.enable -- globally enables the dconf configuration system.";
    };



    freshEditor = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "home-manager programs.fresh-editor.enable (terminal editor).";
      };
      defaultEditor = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "home-manager programs.fresh-editor.defaultEditor -- sets EDITOR/VISUAL via home.sessionVariables.";
      };
      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "home-manager programs.fresh-editor.extraPackages -- language servers on PATH for fresh's built-in lsp.<language-id> map.";
      };
    };
  };
}
