# &desc: "VS Code Python extensions -- debugpy, base Python support, Pylance, Python environment management, and Black formatting."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      ms-python.black-formatter
      ms-python.debugpy
      ms-python.python
      ms-python.vscode-pylance
      ms-python.vscode-python-envs
    ];
}
