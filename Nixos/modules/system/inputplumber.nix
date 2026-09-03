# &desc: "Declares + wires config.vars.system.inputplumber (services.inputplumber daemon) -- system-wide controller-translation, remaps PlayStation/other pads into a virtual XInput device so Wine/Bottles/Proton apps see a gamepad without per-game Steam Input."

{ config, lib, ... }:

# One flat file -- same reasoning as ./openrazer.nix. Real value lives in
# config/system/inputplumber.nix.
{
  options.vars.system.inputplumber.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "services.inputplumber.enable.";
  };

  config = lib.mkIf config.vars.system.inputplumber.enable {
    services.inputplumber.enable = true;
  };
}
