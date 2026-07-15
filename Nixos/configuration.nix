{ config, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./variables.nix
    ./modules
    ./config
  ];

  system.stateVersion = config.vars.stateVersion;
}
