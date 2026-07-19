# &desc: "Programs config imports -- personal picks with no sensible generic default: gaming stack, silentSDDM's wallpaper, editor+LSP list, and VSCode."

{ ... }:

# -------------------------------------------------------------------------
# IMPORTANT: Defaults need to be wired into modules/packages/default.nix
# first to add programs here!
# -------------------------------------------------------------------------

# Personal picks that have no sensible generic default -- the gaming stack,
# silentSDDM's wallpaper, and the editor+LSP list. fish/hyprland/direnv/
# nix-ld stay as real defaults in modules/packages/programs/default.nix
# since the rest of this repo already assumes them regardless of who's
# cloning it. See that file for the schema this fills in. One file per
# app -- same reasoning as config/self-hosted's per-service split.
{
  imports = [
    ./dconf.nix
    ./fresh-editor.nix
    ./gamemode.nix
    ./gamescope.nix
    ./silent-sddm.nix
    ./steam.nix
    ./vscode
  ];
}
