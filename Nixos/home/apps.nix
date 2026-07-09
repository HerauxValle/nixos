{ config, pkgs, ... }:

{
  xdg.configFile = {
    "hypr".source = ../../Hyprland;
    "kitty".source = ../../Kitty;
    "quickshell".source = ../../Quickshell;
    "uwsm/env-hyprland".source = ../../Hyprland/Uwsm/env-hyprland;

    # Not Hyprland-specific (Pacnix, Run, Reload, etc. are general-purpose),
    # so it's its own top-level folder/XDG dir, same pattern as the others.
    "scripts".source = ../../Scripts;

    # Same plain copy as everything else above. theme.py (run manually,
    # live -- see Scripts/Reload/theme.py) writes config.jsonc and
    # colors.env straight into Dotfiles/Fastfetch/; this just picks up
    # whatever's there at rebuild time, same as any other dotfile.
    "fastfetch".source = ../../Fastfetch;

    # Gwenview's "Auto" background mode literally means "Follow color scheme"
    # (see lib/documentview/documentviewcontroller.cpp) -- the same active
    # KDE color scheme Dolphin already uses, including whatever gives it its
    # translucent/blurred panel. Explicitly setting Dark (previous attempt)
    # hardcodes a fixed opaque paint instead, bypassing that scheme entirely.
    "gwenviewrc" = {
      force = true; # gwenview had already written its own copy imperatively;
                    # home-manager refuses to clobber existing files otherwise.
      text = ''
        [General]
        BackgroundColorMode=DocumentView::Dark
      '';
    };
  };

  # Declarative Proton GE: symlinks nixpkgs' proton-ge-bin into Steam's compat
  # tools dir. Version is whatever nixpkgs pins; bumps on flake update + rebuild,
  # no protonup/imperative download step needed. Force-check the tool in
  # Properties > Compatibility after a version bump.
  xdg.dataFile."Steam/compatibilitytools.d/GE-Proton".source = pkgs.proton-ge-bin;

  # ~/.local/bin is earlier in $PATH than real sudo (/run/wrappers/bin),
  # so this is what actually makes it intercept "sudo" -- lib/*.sh
  # resolves via the fixed XDG path in Scripts/Sudo/sudo itself, not via
  # this file's own location, so a plain copy is enough.
  #
  # Unwired for now (2026-07-05): real bugs found in the broker's
  # argument handling -- see Scripts/Sudo/bug.md. Re-enable once fixed.
  # home.file.".local/bin/sudo".source = ../../Scripts/Sudo/sudo;
}