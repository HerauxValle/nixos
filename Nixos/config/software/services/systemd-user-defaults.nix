# &desc: "Systemd user manager defaults -- dark GTK theme + Hyprland desktop context propagated to all user services and portals."

{ ... }:

{
  # Systemd manager top-level user configuration block. Enforces fallback
  # desktop context environments and dark appearance parameters downstream to
  # all standard child processes, desktop portal file-selection dialog arrays,
  # and modular Wayland surface targets spawned under the display target stack.
  # Essential because isolated backend portals lack direct knowledge of the active
  # window manager's theme parameters and default to raw light mode otherwise.
  systemd.user.settings.Manager = {
    DefaultEnvironment = "GTK_THEME=Adwaita:dark GTK_DARK_THEME=1 XDG_CURRENT_DESKTOP=Hyprland";
  };
}
