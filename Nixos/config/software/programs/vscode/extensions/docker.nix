# &desc: "VS Code Docker extensions -- container create/manage/debug via Microsoft's actively-maintained Container Tools extension (not the deprecated vscode-docker or the competing docker.docker)."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      ms-azuretools.vscode-containers
    ];
}
