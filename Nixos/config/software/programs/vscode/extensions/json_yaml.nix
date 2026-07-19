# &desc: "VS Code JSON/YAML/TOML extensions -- rich JSON Schema validation, autocompletion, YAML support, and full TOML tooling."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      redhat.vscode-yaml
      tamasfe.even-better-toml
    ];
}
