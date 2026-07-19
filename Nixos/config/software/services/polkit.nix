# &desc: "Polkit privilege escalation with GNOME auth agent (dark-themed) as systemd user service for graphical sudo prompts."

{ pkgs, ... }:

{
  # Core Polkit privilege escalation framework backend. Required to handle local
  # administrative permissions validation seamlessly in a non-monolithic desktop
  # environment without falling back to raw command-line sudo interception.
  security.polkit.enable = false;

  # Graphical session agent configuration. Manages user-level authentication
  # challenges for high-privilege system and service operations.
  systemd.user.services.polkit-gnome-authentication-agent-1 = {
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
}
