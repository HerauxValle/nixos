# &desc: "VS Code extension settings -- extension-manager auto-update plus per-extension config for todo-tree, Nix LSP, and nix-embedded-languages."

{ config, pkgs, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.userSettings =
    {
      # ============================================================
      # Extensions
      # ============================================================
      "extensions.autoCheckUpdates" = true;
      "extensions.autoUpdate" = "on";
      # ============================================================
      # Todo Tree
      # ============================================================
      # Real store path instead of hardcoding the current system
      # generation's /run/current-system/sw/bin/rg, which breaks
      # under rollbacks or a standalone home-manager profile.
      "todo-tree.ripgrep.ripgrep" = "${pkgs.ripgrep}/bin/rg";
      # ============================================================
      # Nix
      # ============================================================
      "nix.enableLanguageServer" = true;
      "nix.serverPath" = "nil";
      "nix-embedded-languages.variableMarkers.suffix" = {
        Script = "shell";
      };
      "nix-embedded-languages.variableMarkers.prefix" = {
        py = "python";
      };
      "nix-embedded-languages.functionBindings" = {
        "writePython3|writePyPy3" = "python";
      };
    };
}
