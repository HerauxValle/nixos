# &desc: "VS Code Python extensions -- debugpy, base Python support, Pylance, and Python environment management."

{ config, pkgs, ... }:

{
  config.home-manager.users.${config.vars.identity.username}.programs.vscode.profiles.default.extensions =
    with pkgs.vscode-extensions; [
      ms-python.debugpy
      ms-python.python
      ms-python.vscode-pylance
      ms-python.vscode-python-envs
    ];
}
