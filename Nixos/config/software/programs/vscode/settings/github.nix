{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.userSettings =
    {
      # ============================================================
      # Github
      # ============================================================
      "github.copilot.nextEditSuggestions.enabled" = false;
      "github.copilot.enable" = {
        "*" = false;
        plaintext = false;
        markdown = false;
        scminput = false;
      };
      # ============================================================
      # Git
      # ============================================================
      "git.autofetch" = true;
      "git.confirmSync" = false;
      "git.enableSmartCommit" = true;
    };
}
