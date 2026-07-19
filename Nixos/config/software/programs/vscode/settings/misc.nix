# &desc: "VS Code one-off settings that don't warrant their own file -- chat MCP gallery, quick-open search history."

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
    };
}
