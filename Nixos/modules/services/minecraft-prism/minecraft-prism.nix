# &desc: "Wires vars.minecraft.prism.{portable,location} into a home-manager activation script that symlinks $XDG_DATA_HOME/PrismLauncher to that location."

{ config, lib, inputs, ... }:

let
  cfg = config.vars.minecraft.prism;
  homeCfg = config.home-manager.users.${config.vars.identity.username};
in

# Prism Launcher's own portable mode only works by dropping a portable.txt
# marker next to the executable, so the app treats that directory as its
# root -- fundamentally incompatible with Nix packaging, since the binary
# lives at an immutable, per-rebuild /nix/store/<hash>-.../bin/prismlauncher
# path. This reproduces the same effect the Nix way: symlink
# $XDG_DATA_HOME/PrismLauncher to cfg.location, so Prism and
# programs.prismlauncher's own settings-merge/themes/icons writes all land
# under one portable folder, without changing how any of that is managed
# (still the same "controlled impurity" cfg merge, still the same
# app-UI-managed instances/mods/worlds -- see config/software/programs/
# prism/default.nix for that side).
{
  # Runs before linkGeneration so the symlink is already in place by the
  # time programs.prismlauncher's own settings-merge/themes/icons home.file
  # entries land -- otherwise a first activation could write those into a
  # real directory that this then has to migrate out from under itself.
  #
  # One-time migration (real dir -> cfg.location) only fires while
  # $XDG_DATA_HOME/PrismLauncher is still a real directory; once it's a
  # symlink the [ ! -L ] check skips straight to the ln -sfn, which is a
  # no-op if already correct. Safe to flip portable back to false later:
  # nothing here ever deletes cfg.location, it just stops maintaining the
  # symlink, so Prism falls back to writing a fresh real directory at the
  # default XDG path on next launch.
  config.home-manager.users.${config.vars.identity.username}.home.activation.prismPortableSymlink =
    lib.mkIf cfg.portable (
      inputs.home-manager.lib.hm.dag.entryBefore [ "linkGeneration" ] ''
        target="${homeCfg.xdg.dataHome}/PrismLauncher"
        portable=${lib.escapeShellArg cfg.location}

        if [ -e "$target" ] && [ ! -L "$target" ]; then
          $DRY_RUN_CMD mkdir -p "$portable"
          $DRY_RUN_CMD cp -a "$target"/. "$portable"/
          $DRY_RUN_CMD rm -rf "$target"
        fi

        $DRY_RUN_CMD mkdir -p "$(dirname "$portable")"
        $DRY_RUN_CMD ln -sfn "$portable" "$target"
      ''
    );
}
