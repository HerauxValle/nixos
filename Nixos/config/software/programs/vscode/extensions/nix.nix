# &desc: "VS Code Nix extensions -- syntax highlighting and the nix-ide language client."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      bbenoist.nix
      jnoortheen.nix-ide
    ];
}
