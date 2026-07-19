# &desc: "VS Code one-off settings that don't warrant their own file -- chat MCP gallery, quick-open search history, docker-run auto-config prompt."

{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.userSettings =
    {
      # ============================================================
      # Chat
      # ============================================================
      "chat.mcp.gallery.enabled" = true;
      # ============================================================
      # Search
      # ============================================================
      "search.quickOpen.includeHistory" = true;
      # ============================================================
      # Docker Run (george3447.docker-run)
      # ============================================================
      # Suppresses "Do you want to add containers for this workspace?" on
      # every startup -- that's this extension's own first-run scaffolding
      # prompt, not the Container Tools extension.
      "DockerRun.DisableAutoGenerateConfig" = true;
    };
}
