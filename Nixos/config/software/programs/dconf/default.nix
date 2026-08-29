# &desc: "dconf program config -- configuration engine enabled for XDG desktop portals and Wayland session daemons."

{ ... }:

{
  # dconf configuration engine. Essential layer for standard XDG desktop portals
  # and modular environment daemons (like polkit-gnome-authentication-agent-1)
  # running in minimal Wayland sessions. Without this registry enabled, core
  # GTK/GIO dialog wrappers fail to look up user preference paths, falling back
  # to raw un-themed white default layouts rather than honoring global systemd
  # environment settings or customized dark-mode themes.
  config.vars.packages.programs.dconf = {
    enable = true;

    # GTK/libadwaita apps (Bottles, etc.) read dark/light mode from this key
    # via the XDG desktop portal, independent of Hyprland's own theme --
    # xdg-desktop-portal-hyprland doesn't implement
    # org.freedesktop.impl.portal.Settings, so it falls through to
    # xdg-desktop-portal-gtk, which reads this key.
    settings."org/gnome/desktop/interface".color-scheme = "prefer-dark";
  };
}
