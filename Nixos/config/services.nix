{ config, pkgs, ... }:

{
  # Core Polkit privilege escalation framework backend. Required to handle local
  # administrative permissions validation seamlessly in a non-monolithic desktop
  # environment without falling back to raw command-line sudo interception.
  security.polkit.enable = false;

  # Graphical session agent configuration. Manages user-level authentication
  # challenges for high-privilege system and service operations.
  systemd.user = {
    services = {
      polkit-gnome-authentication-agent-1 = {
        description = "polkit-gnome-authentication-agent-1";
        wantedBy = [ "graphical-session.target" ];
        wants = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
          RestartSec = 1;
          TimeoutStopSec = 10;

          # GTK engine styling target overrides. Dictates dark variant execution
          # constraints natively within the sandboxed authentication agent process
          # to isolate visual structure configuration from global window manager state.
          Environment = "GTK_THEME=Adwaita:dark GTK_DARK_THEME=1";
        };
      };
    };

    # Systemd manager top-level user configuration block. Enforces fallback
    # desktop context environments and dark appearance parameters downstream to
    # all standard child processes, desktop portal file-selection dialog arrays,
    # and modular Wayland surface targets spawned under the display target stack.
    # Essential because isolated backend portals lack direct knowledge of the active
    # window manager's theme parameters and default to raw light mode otherwise.
    settings.Manager = {
      DefaultEnvironment = "GTK_THEME=Adwaita:dark GTK_DARK_THEME=1 XDG_CURRENT_DESKTOP=Hyprland";
    };
  };
}
