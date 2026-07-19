# &desc: "VS Code Go extensions -- rich Go language support via gopls."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      golang.go
    ];
}
