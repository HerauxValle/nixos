# &desc: "Enables the gamepad-to-XInput bridge -- schema + wiring live in ../../modules/system/gamepad-bridge.nix."

{ config, ... }:

{
  config.vars.system.gamepadBridge = {
    enable = true;
    user = config.vars.identity.username;
    restart = "on-failure";
    restartSec = "5";
  };
}
