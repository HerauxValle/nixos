{ config, pkgs, ... }:

{
  # 1. Enable the core Polkit framework backend
  security.polkit.enable = false;

  # 3. Create a systemd user service to automatically manage the agent daemon
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
          Environment = "GTK_THEME=Adwaita:dark GTK_DARK_THEME=1";
        };
      };
    };

    settings.Manager = {
      DefaultEnvironment = "GTK_THEME=Adwaita:dark GTK_DARK_THEME=1 XDG_CURRENT_DESKTOP=Hyprland";
    };
  };

  # Enable dconf globally out of the custom vars scope
  programs.dconf.enable = false;
}
