# &desc: "VS Code keybindings -- custom keyboard shortcuts."

{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.keybindings =
    [
      {
        key = "ctrl+t";
        command = "workbench.action.terminal.toggleTerminal";
      }
    ];
}
