{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.userSettings =
    {
      # ============================================================
      # Terminal
      # ============================================================
      "terminal.integrated.smoothScrolling" = true;
      "terminal.integrated.cursorBlinking" = true;
      "terminal.integrated.gpuAcceleration" = "auto";
      # Uncomment if you use fish
      # "terminal.integrated.defaultProfile.linux" = "fish";
    };
}
