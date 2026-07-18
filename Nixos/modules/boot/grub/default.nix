{ lib, ... }:

{
  imports = [ ./grub.nix ];

  options.vars.boot.grub = {
    # GRUB theme directory, containing background, selection graphics,
    # terminal box borders, custom fonts, and theme.txt.
    # Points into Dotfiles/Themes/GRUB/BSOL, four levels up from this file's
    # location (Nixos/modules/boot/grub/default.nix).
    # Genuine reproducible reference, not a hardcoded literal -- the entire
    # theme folder lives in the repo, resolves correctly on any fresh clone.
    grubThemePath = lib.mkOption {
      type = lib.types.path;
      default = ../../../../Themes/GRUB/BSOL;
      description = "GRUB theme directory (background, selection graphics, fonts, theme.txt).";
    };

    # Screen resolution GRUB renders the graphical theme at.
    # Matches the monitor's native resolution for correct scaling.
    gfxResolution = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = "Screen resolution GRUB renders the graphical theme at.";
    };

    # true  = menu hidden by default, reveal with ESC during boot
    # false = menu always shown, normal countdown timeout
    hidden = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Hide the boot menu by default (reveal with ESC) instead of always showing it.";
    };

    # true  = graphical mode (gfxterm), theme/background/fonts render
    # false = plain text console mode, no theme, more portable across hardware
    graphical = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Graphical (gfxterm, themed) boot menu instead of plain text console mode.";
    };
  };
}
