# &desc: "VS Code C/C++ extensions -- IntelliSense, debugging, code browsing, and CMake tooling (the cpptools-extension-pack's members, split across nixpkgs/custom.nix by what's actually packaged)."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      ms-vscode.cmake-tools
      ms-vscode.cpptools
      # cpptools-themes + cpp-devtools (the pack's other two members) aren't
      # packaged in nixpkgs -- see custom.nix.
    ];
}
