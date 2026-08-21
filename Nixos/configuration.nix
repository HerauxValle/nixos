# &desc: "NixOS configuration root -- imports hardware-configuration, schema (variables), all modules, and per-machine config values."

{ config, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./variables.nix
    ./modules
    ./config
  ];

  system.stateVersion = config.vars.identity.stateVersion;
}
