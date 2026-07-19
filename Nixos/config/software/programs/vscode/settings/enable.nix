# &desc: "VS Code enable -- fully declarative (mutableExtensionsDir = false), extensions/keybindings/settings managed entirely by Nix."

{ config, ... }:

{
  # Home-manager-only programs.* (not a NixOS system option, so it can't go
  # through config.vars.packages.programs -> modules/packages/programs/programs.nix
  # like the rest of this directory).
  config.home-manager.users.${config.vars.identity.username}.programs.vscode = {
    enable = false;
    # Extensions are fully declared in ../extensions -- don't let VS Code's
    # own UI install/mutate extensions outside of Nix.
    mutableExtensionsDir = false;
  };
}
