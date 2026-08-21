# &desc: "VS Code Rust extensions -- rust-analyzer LSP."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      # Already handles your Rust LSP (rust-analyzer)
      rust-lang.rust-analyzer
    ];
}
