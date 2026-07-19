# &desc: "VS Code appearance -- icon theme, window chrome, editor tabs, and workbench tree/activity-bar layout."

{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.userSettings =
    {
      # ============================================================
      # Appearance
      # ============================================================
      "workbench.iconTheme" = "material-icon-theme";
      "workbench.startupEditor" = "none";
      "workbench.editor.enablePreview" = true;
      "workbench.editor.enablePreviewFromQuickOpen" = true;
      "workbench.editor.highlightModifiedTabs" = true;
      "workbench.tree.renderIndentGuides" = "always";
      "workbench.tree.indent" = 16;
      "workbench.activityBar.compact" = true;
      "workbench.activityBar.autoHide" = true;
      "workbench.activityBar.location" = "top";
      "window.commandCenter" = false;
      "window.menuBarVisibility" = "toggle";
      "breadcrumbs.enabled" = true;
    };
}
