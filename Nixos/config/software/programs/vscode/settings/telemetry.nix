# &desc: "VS Code telemetry -- disables feedback prompts, telemetry level, and edit-stats collection."

{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.userSettings =
    {
      # ============================================================
      # Telemetry
      # ============================================================
      "telemetry.feedback.enabled" = false;
      "telemetry.telemetryLevel" = "off";
      "telemetry.editStats.enabled" = false;
    };
}
