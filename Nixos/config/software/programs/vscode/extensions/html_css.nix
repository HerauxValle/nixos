# &desc: "VS Code HTML/CSS extensions -- HTML CSS support, auto-close and auto-rename tag."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      ecmel.vscode-html-css
      formulahendry.auto-close-tag
      formulahendry.auto-rename-tag
      # bradlc.vscode-tailwindcss # (Optional) Uncomment if you use Tailwind CSS
    ];
}
