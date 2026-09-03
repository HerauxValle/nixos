# &desc: "Enables sc-controller (DS4/generic pad -> XInput translation) -- schema + wiring live in ../../modules/system/sc-controller.nix."

{ config, pkgs, ... }:

{
  config.vars.system.scController = {
    enable = true;
    package = pkgs.sc-controller;
    user = config.vars.identity.username;
    daemonFlags = [ "--alone" "--foreground" ];
    restart = "on-failure";
    restartSec = "5";
  };
}
