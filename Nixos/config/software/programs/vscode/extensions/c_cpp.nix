# &desc: "VS Code C/C++ extensions -- IntelliSense, debugging, and code browsing."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      ms-vscode.cpptools
      # twxs.cmake # (Optional) Uncomment if you use CMake
    ];
}
