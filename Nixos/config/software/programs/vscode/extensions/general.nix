# &desc: "VS Code general/cross-language extensions -- todo tree, icon theme, direnv, editorconfig, prettier, gitlens."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      gruntfuggly.todo-tree
      pkief.material-icon-theme

      # Loads development environment shell (highly recommended)
      mkhl.direnv
      # Standardizes editor configs across teams
      editorconfig.editorconfig
      # Opinionated code formatter (highly recommended); also formats JSON, JSONC, and markdown
      esbenp.prettier-vscode
      # Supercharged Git visualization (highly recommended)
      eamodio.gitlens
    ];
}
