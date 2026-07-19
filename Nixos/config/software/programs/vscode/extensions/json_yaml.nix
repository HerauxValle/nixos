# &desc: "VS Code JSON/YAML extensions -- rich JSON Schema validation, autocompletion, and YAML support."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      redhat.vscode-yaml
    ];
}
