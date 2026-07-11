{ config, pkgs, ... }:

# Personal picks -- which per-directory shells YOU want. No options.vars
# declaration needed here, same as config/customized.nix -- that lives in
# defaults/packages/shells.nix instead.
#
# Each entry: a path, the packages that should be on $PATH while inside
# it, and whether that also applies to subdirectories (default true --
# e.g. Dotfiles/Hyprland inherits Dotfiles' shell unless recursive is
# set false here). Nothing is installed system-wide; packages only
# exist on $PATH while cwd matches. See modules/packages/shells.nix for
# the direnv-generation logic that consumes this.
{
  config.vars.shells = [

    {
      path = "${config.vars.homeDirectory}/Dotfiles";
      packages = with pkgs; [ tmux ];
      # recursive = true; # default
    }

  ];
}
