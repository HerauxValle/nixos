# &desc: "VS Code shell script extensions -- ShellCheck linting and shell script formatting."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      foxundermoon.shell-format
      timonwong.shellcheck
    ];
}
